import AppKit
import Foundation

/// Seul endroit qui traduit une `Action` en effet réel.
/// La machine à états décide, le coordinateur exécute.
public final class Coordinateur: NSObject, NSMenuDelegate {
    public static let gardeAppui: TimeInterval = 0.25
    public static let dureeMaximale: TimeInterval = 180
    public static let delaiWorker: TimeInterval = 30
    public static let fenetreTripleAppui: TimeInterval = 0.9
    public static let appuisPourHistorique = 3

    private var machine = MachineEtats()
    private let micro = Micro()
    private let pastille = Pastille()
    private let transcripteur: Transcripteur
    private var declencheur: Declencheur?

    private var gardeEnCours: DispatchWorkItem?
    private var dureeMaxEnCours: DispatchWorkItem?
    private var wavCourant: URL?
    private var dernierDelai: Double = 0
    private var configuration: Configuration
    private let audios = AudioEnAttente()
    private let fileAudio = DispatchQueue(label: "dictee.audio.fichiers", qos: .userInitiated)
    private var barre: NSStatusItem?
    private var nettoyage: Timer?
    private var relachementDepuis: TimeInterval?


    private let historique: Historique
    private lazy var fenetreHistorique: FenetreHistorique = {
        let f = FenetreHistorique(historique: historique)
        f.surRecoller = { texte, app in
            Reactivation.collerDans(app, texte: texte, surJournal: { journaliser($0) })
        }
        return f
    }()

    public init(racine: URL) {
        let config = Configuration.charger()
        configuration = config
        transcripteur = Transcripteur(
            executable: racine.appendingPathComponent(".venv/bin/python"),
            arguments: [racine.appendingPathComponent("worker/transcribe.py").path],
            delai: Coordinateur.delaiWorker,
            inactivite: config.toujoursPret ? 0 : config.inactiviteSecondes,
            purgeApres: config.purgeSecondes, cacheMo: config.cacheMo)
        historique = Historique(fichier: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dictee/historique.jsonl"))
        super.init()
    }

    /// Ne sort jamais sur une autorisation manquante : la pastille reste rouge
    /// et l'app démarre d'elle-même dès que l'utilisateur accorde. Sortir
    /// mettrait le LaunchAgent en boucle de relance.
    public func demarrer() {
        attendreLesAutorisations()
    }

    private var autorisationsDemandees = false

    private func autorisationManquante() -> String? {
        if !Declencheur.autorisationAccordee() { return "surveillance des entrées" }
        if !Declencheur.accessibiliteAccordee() { return "accessibilité" }
        // Le micro est attendu au démarrage, pas au milieu d'une dictée : une
        // boîte de dialogue pendant un push-to-talk ferait perdre la phrase.
        if !Micro.autorisationAccordee() { return "micro" }
        return nil
    }

    private func attendreLesAutorisations() {
        guard let quoi = autorisationManquante() else {
            do { try demarrerVraiment() }
            catch { journaliser("démarrage impossible : \(error)") }
            return
        }

        if !autorisationsDemandees {
            autorisationsDemandees = true
            Declencheur.demanderAutorisation()
            Declencheur.demanderAccessibilite()
            Micro.demanderAutorisation()
            journaliser("⚠️ autorisation manquante : \(quoi)")
            journaliser("   Réglages → Confidentialité et sécurité → ajouter Dictee.app")
            journaliser("   j'attends ; la dictée démarrera toute seule dès que ce sera accordé")
        }
        pastille.afficher(.erreur(quoi), persistant: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.attendreLesAutorisations()
        }
    }

    private func demarrerVraiment() throws {
        pastille.afficher(.repos)
        micro.preparer()
        micro.surNiveau = { [weak self] db in self?.pastille.niveau(db) }
        transcripteur.surJournal = { journaliser($0) }
        transcripteur.surPreparation = { [weak self] preparation in
            guard let self, machine.etat == .transcription else { return }
            pastille.afficher(preparation ? .preparation : .transcription)
        }
        if configuration.toujoursPret { try transcripteur.demarrer() }
        installerMenu()
        nettoyerAudio()
        nettoyage = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.nettoyerAudio()
        }

        let d = Declencheur { [weak self] signal in
            guard let self else { return }
            switch signal {
            case .appui:
                instantAppui = Date()
                appliquer(machine.recevoir(.appui))
            case .relachement:
                let bref = instantAppui.map {
                    Date().timeIntervalSince($0) < Coordinateur.gardeAppui
                } ?? false
                instantAppui = nil
                appliquer(machine.recevoir(.relachement))
                if bref { compterAppuiBref() }
            case .autreTouche:
                if case .capture = machine.etat { journaliser("capture annulée : autre touche pendant ⌘ droite") }
                appliquer(machine.recevoir(.autreTouche))
            }
        }
        try d.demarrer()
        declencheur = d

        pastille.surClic = { [weak self] in
            guard let self else { return }
            appliquer(machine.recevoir(.clicPastille))
        }
        historique.surJournal = { journaliser($0) }
        DispatchQueue.global(qos: .utility).async { [historique] in
            historique.charger()
            DispatchQueue.main.async {
                journaliser("historique : \(historique.entrees.count) dictée(s) chargée(s)")
            }
        }

        journaliser("Dictée \(Version.courante) — maintiens ⌘ droite pour dicter")
    }

    private func appliquer(_ actions: [Action]) {
        for a in actions { executer(a) }
    }

    // ── comptage des appuis brefs ─────────────────────────────────────────

    private var instantAppui: Date?
    private var appuisBrefs = 0
    private var fenetreTriple: DispatchWorkItem?

    /// Un appui bref est un relâchement avant la garde. Le comptage vit ici et
    /// pas dans la machine à états : c'est du temps, et la machine doit rester
    /// pure pour rester testable.
    private func compterAppuiBref() {
        appuisBrefs += 1
        fenetreTriple?.cancel()
        if appuisBrefs >= Coordinateur.appuisPourHistorique {
            appuisBrefs = 0
            injecter(.tripleAppui)
            return
        }
        let t = DispatchWorkItem { [weak self] in self?.appuisBrefs = 0 }
        fenetreTriple = t
        DispatchQueue.main.asyncAfter(deadline: .now() + Coordinateur.fenetreTripleAppui,
                                      execute: t)
    }

    /// Réinjecte un événement produit par une action, **après** la fin du lot
    /// en cours. Le faire en direct traiterait le nouvel état au milieu du
    /// précédent : les actions restantes l'écraseraient (le rotor de
    /// transcription recouvrait l'annulation, et ne partait plus jamais).
    private func injecter(_ e: Evenement) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            appliquer(machine.recevoir(e))
        }
    }

    private func executer(_ action: Action) {
        switch action {
        case .preparerModele:
            transcripteur.preparer()

        case .demarrerCapture:
            pastille.repositionner()
            do { try micro.demarrer(); journaliser("capture micro démarrée") }
            catch {
                journaliser("micro indisponible : \(error)")
                injecter(.echec("micro indisponible"))
            }

        case .armerGarde:
            gardeEnCours = planifier(Coordinateur.gardeAppui) { [weak self] in
                guard let self else { return }
                appliquer(machine.recevoir(.gardeEcoulee))
            }

        case .armerDureeMax:
            dureeMaxEnCours = planifier(Coordinateur.dureeMaximale) { [weak self] in
                guard let self else { return }
                journaliser("coupure de sécurité à \(Int(Coordinateur.dureeMaximale)) s")
                appliquer(machine.recevoir(.dureeMax))
            }

        case .desarmerMinuteries:
            gardeEnCours?.cancel(); gardeEnCours = nil
            dureeMaxEnCours?.cancel(); dureeMaxEnCours = nil

        case .abandonnerCapture:
            let abandonnes = micro.arreter()
            journaliser("capture abandonnée : \(abandonnes.count) échantillons")
            transcripteur.finCapture()

        case .cloturerCapture:
            relachementDepuis = ProcessInfo.processInfo.systemUptime
            let echantillons = micro.arreter()
            let audios = self.audios
            // Analyse et sérialisation hors de la file UI. La machine reste en
            // transcription et refuse une seconde capture pendant cette étape.
            fileAudio.async { [weak self] in
                let parlees = AudioWAV.secondesParlees(echantillons)
                let pic = echantillons.reduce(Float(0)) { max($0, abs($1)) }
                let db = pic > 0 ? 20 * log10(pic) : -120
                journaliser(String(format: "capture terminée : %d échantillons, %.3f s, pic %.1f dBFS, %.3f s au-dessus du seuil",
                                   echantillons.count, Double(echantillons.count) / 16000, db, parlees))
                do {
                    let wav = parlees >= MachineEtats.secondesParoleMinimum
                        ? try audios.ajouter(echantillons) : nil
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        wavCourant = wav
                        if wav == nil { transcripteur.finCapture() }
                        injecter(.captureAnalysee(secondesParlees: parlees))
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        transcripteur.finCapture()
                        journaliser("écriture WAV impossible : \(error)")
                        injecter(.echec("écriture WAV impossible"))
                    }
                }
            }

        case .envoyerAuWorker:
            guard let wav = wavCourant else {
                injecter(.echec("aucun audio à transcrire")); return
            }
            transcripteur.transcrire(wav) { [weak self] resultat in
                guard let self else { return }
                wavCourant = nil
                switch resultat {
                case .success(let r):
                    do { try audios.supprimer(wav) }
                    catch { journaliser("nettoyage audio impossible : \(error)") }
                    dernierDelai = r.secondes
                    journaliser("transcription terminée : \(r.secondes) s, \(r.texte.count) caractères")
                    appliquer(machine.recevoir(.texteRecu(r.texte)))
                case .failure(let e):
                    journaliser("⚠️ \(e)")
                    journaliser("audio conservé 24 h ; menu Dictée → Réessayer")
                    appliquer(machine.recevoir(.echec(message(e) + " — menu Dictée pour réessayer")))
                }
            }
            transcripteur.finCapture()

        case .ouvrirHistorique:
            fenetreHistorique.ouvrir()

        case .coller(let texte):
            Collage.coller(texte)
            if let debut = relachementDepuis {
                journaliser(String(format: "latence relâchement → collage envoyé : %.3f s",
                                   ProcessInfo.processInfo.systemUptime - debut))
            }
            relachementDepuis = nil
            // Perdre l'archive ne doit jamais faire perdre le texte : on colle
            // d'abord, on archive ensuite, et un échec d'écriture ne fait que
            // partir au journal.
            do { try historique.ajouter(texte: texte, secondes: dernierDelai) }
            catch { journaliser("historique non écrit : \(error)") }

        case .pastille(let etat):
            pastille.afficher(etat)
        }
    }

    private func installerMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictée")
        item.button?.toolTip = "Dictée — réglages et dictées à réessayer"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        item.menu = menu; barre = item
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        @discardableResult func ajouter(_ titre: String, _ action: Selector? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: titre, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item); return item
        }
        let statut = machine.etat == .transcription ? "Transcription en cours"
            : (transcripteur.pret ? "Modèle prêt" : "Modèle en veille ou en préparation")
        ajouter(statut).isEnabled = false
        menu.addItem(.separator())
        let mode = ajouter("Toujours garder le modèle prêt", #selector(changerMode))
        mode.state = configuration.toujoursPret ? .on : .off
        ajouter("Mode équilibré : veille après \(Int(configuration.inactiviteSecondes / 60)) min").isEnabled = false
        menu.addItem(.separator())
        let fichiers = audios.fichiers
        let titre = fichiers.isEmpty ? "Aucune dictée à réessayer" : "Réessayer une dictée (\(fichiers.count))"
        let parent = ajouter(titre)
        parent.isEnabled = !fichiers.isEmpty && machine.etat == .repos
        if !fichiers.isEmpty {
            let sousMenu = NSMenu(); sousMenu.autoenablesItems = false
            for wav in fichiers {
                let date = audios.date(wav).formatted(date: .abbreviated, time: .standard)
                let entree = NSMenuItem(title: date, action: #selector(reessayerAudio(_:)), keyEquivalent: "")
                entree.target = self; entree.representedObject = wav
                entree.isEnabled = machine.etat == .repos
                sousMenu.addItem(entree)
            }
            parent.submenu = sousMenu
        }
        ajouter("Les audios en échec expirent après 24 h").isEnabled = false
        ajouter("Ouvrir l’historique", #selector(ouvrirHistoriqueMenu))
        ajouter("Ouvrir le vocabulaire", #selector(ouvrirVocabulaire))
        ajouter("Ouvrir les réglages avancés", #selector(ouvrirConfiguration))
    }

    @objc private func changerMode() {
        var config = configuration; config.toujoursPret.toggle()
        do {
            try config.enregistrer()
            configuration = config
            transcripteur.configurerVeille(config.toujoursPret ? 0 : config.inactiviteSecondes)
            journaliser("mode : \(config.toujoursPret ? "toujours prêt" : "équilibré")")
        } catch { journaliser("réglages non enregistrés : \(error)") }
    }

    @objc private func reessayerAudio(_ item: NSMenuItem) {
        guard machine.etat == .repos, let wav = item.representedObject as? URL,
              FileManager.default.fileExists(atPath: wav.path) else { return }
        wavCourant = wav
        relachementDepuis = ProcessInfo.processInfo.systemUptime
        appliquer(machine.recevoir(.reessayer))
    }

    @objc private func ouvrirHistoriqueMenu() { fenetreHistorique.ouvrir() }
    @objc private func ouvrirVocabulaire() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dictee/vocabulaire.txt"))
    }
    @objc private func ouvrirConfiguration() {
        if !FileManager.default.fileExists(atPath: Configuration.chemin.path) {
            try? configuration.enregistrer()
        }
        NSWorkspace.shared.open(Configuration.chemin)
    }
    private func nettoyerAudio() {
        do { try audios.nettoyer(sauf: wavCourant) }
        catch { journaliser("expiration audio impossible : \(error)") }
    }

    private func planifier(_ delai: TimeInterval, _ bloc: @escaping () -> Void) -> DispatchWorkItem {
        let t = DispatchWorkItem(block: bloc)
        DispatchQueue.main.asyncAfter(deadline: .now() + delai, execute: t)
        return t
    }

    private func message(_ e: ErreurTranscription) -> String {
        switch e {
        case .occupe:           return "transcription déjà en cours"
        case .workerMort:       return "transcripteur arrêté"
        case .delaiDepasse:     return "transcription trop longue"
        case .reponseIllisible: return "réponse illisible"
        case .worker(let m):    return m
        }
    }
}

func journaliser(_ message: String) {
    let h = DateFormatter()
    h.dateFormat = "HH:mm:ss"
    print("\(h.string(from: Date())) \(message)")
    fflush(stdout)
}

import AppKit
import Foundation

/// Seul endroit qui traduit une `Action` en effet réel.
/// La machine à états décide, le coordinateur exécute.
public final class Coordinateur {
    public static let gardeAppui: TimeInterval = 0.25
    public static let dureeMaximale: TimeInterval = 180
    public static let delaiWorker: TimeInterval = 30

    private var machine = MachineEtats()
    private let micro = Micro()
    private let pastille = Pastille()
    private let transcripteur: Transcripteur
    private var declencheur: Declencheur?

    private var gardeEnCours: DispatchWorkItem?
    private var dureeMaxEnCours: DispatchWorkItem?
    private var wavCourant: URL?

    public init(racine: URL) {
        transcripteur = Transcripteur(
            executable: racine.appendingPathComponent(".venv/bin/python"),
            arguments: [racine.appendingPathComponent("worker/transcribe.py").path],
            delai: Coordinateur.delaiWorker)
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
        try transcripteur.demarrer()

        let d = Declencheur { [weak self] signal in
            guard let self else { return }
            switch signal {
            case .appui:       appliquer(machine.recevoir(.appui))
            case .relachement: appliquer(machine.recevoir(.relachement))
            case .autreTouche: appliquer(machine.recevoir(.autreTouche))
            }
        }
        try d.demarrer()
        declencheur = d
        journaliser("Dictée \(Version.courante) — maintiens ⌘ droite pour dicter")
    }

    private func appliquer(_ actions: [Action]) {
        for a in actions { executer(a) }
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
        case .demarrerCapture:
            pastille.repositionner()
            do { try micro.demarrer() }
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
            micro.arreter()

        case .cloturerCapture:
            let echantillons = micro.arreter()
            let parlees = AudioWAV.secondesParlees(echantillons)
            if parlees >= MachineEtats.secondesParoleMinimum {
                do { wavCourant = try micro.ecrireWAV(echantillons) }
                catch {
                    journaliser("écriture WAV impossible : \(error)")
                    injecter(.echec("écriture WAV impossible"))
                    return
                }
            }
            injecter(.captureAnalysee(secondesParlees: parlees))

        case .envoyerAuWorker:
            guard let wav = wavCourant else {
                injecter(.echec("aucun audio à transcrire")); return
            }
            transcripteur.transcrire(wav) { [weak self] resultat in
                guard let self else { return }
                try? FileManager.default.removeItem(at: wav)
                wavCourant = nil
                switch resultat {
                case .success(let r):
                    journaliser("📝 \(r.secondes)s : \(r.texte.prefix(90))")
                    appliquer(machine.recevoir(.texteRecu(r.texte)))
                case .failure(let e):
                    journaliser("⚠️ \(e)")
                    if e == .workerMort { try? transcripteur.demarrer() }
                    appliquer(machine.recevoir(.echec(message(e))))
                }
            }

        case .coller(let texte):
            Collage.coller(texte)

        case .pastille(let etat):
            pastille.afficher(etat)
        }
    }

    private func planifier(_ delai: TimeInterval, _ bloc: @escaping () -> Void) -> DispatchWorkItem {
        let t = DispatchWorkItem(block: bloc)
        DispatchQueue.main.asyncAfter(deadline: .now() + delai, execute: t)
        return t
    }

    private func message(_ e: ErreurTranscription) -> String {
        switch e {
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

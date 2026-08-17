import AppKit
import Foundation

public enum ErreurDemarrage: Error, Equatable {
    case surveillanceRefusee, accessibiliteRefusee
}

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

    public func demarrer() throws {
        guard Declencheur.autorisationAccordee() else {
            Declencheur.demanderAutorisation()
            pastille.afficher(.erreur("surveillance des entrées refusée"))
            throw ErreurDemarrage.surveillanceRefusee
        }
        guard Declencheur.accessibiliteAccordee() else {
            pastille.afficher(.erreur("accessibilité refusée"))
            throw ErreurDemarrage.accessibiliteRefusee
        }

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

    private func executer(_ action: Action) {
        switch action {
        case .demarrerCapture:
            pastille.repositionner()
            do { try micro.demarrer() }
            catch {
                journaliser("micro indisponible : \(error)")
                appliquer(machine.recevoir(.echec("micro indisponible")))
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
                    appliquer(machine.recevoir(.echec("écriture WAV impossible")))
                    return
                }
            }
            appliquer(machine.recevoir(.captureAnalysee(secondesParlees: parlees)))

        case .envoyerAuWorker:
            guard let wav = wavCourant else {
                appliquer(machine.recevoir(.echec("aucun audio à transcrire"))); return
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

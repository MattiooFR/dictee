import Foundation

public enum EtatPastille: Equatable {
    case repos, ecoute, transcription, succes, annule
    case erreur(String)
}

public enum Evenement: Equatable {
    case appui, gardeEcoulee, relachement, autreTouche, dureeMax
    case captureAnalysee(secondesParlees: Double)
    case texteRecu(String)
    case echec(String)
}

public enum Action: Equatable {
    case demarrerCapture, armerGarde, armerDureeMax, desarmerMinuteries
    case abandonnerCapture, cloturerCapture, envoyerAuWorker
    case coller(String)
    case pastille(EtatPastille)
}

/// Décide quoi faire, ne fait rien. Aucun accès au clavier, au micro ni à
/// l'écran : c'est ce qui la rend testable en totalité.
public struct MachineEtats {
    public enum Etat: Equatable { case repos, capture(gardeFranchie: Bool), transcription }

    public private(set) var etat: Etat = .repos
    public static let secondesParoleMinimum: Double = 0.4

    public init() {}

    public mutating func recevoir(_ e: Evenement) -> [Action] {
        switch (etat, e) {
        case (.repos, .appui):
            // La capture démarre avant la garde : attendre ferait perdre le premier mot.
            etat = .capture(gardeFranchie: false)
            return [.demarrerCapture, .armerGarde, .armerDureeMax]

        case (.capture(gardeFranchie: false), .gardeEcoulee):
            etat = .capture(gardeFranchie: true)
            return [.pastille(.ecoute)]

        case (.capture(gardeFranchie: false), .relachement):
            etat = .repos
            return [.desarmerMinuteries, .abandonnerCapture, .pastille(.annule)]

        case (.capture(gardeFranchie: _), .autreTouche):
            // C'était un raccourci ⌘ droite + touche : aucun retour visuel.
            etat = .repos
            return [.desarmerMinuteries, .abandonnerCapture, .pastille(.repos)]

        case (.capture(gardeFranchie: true), .relachement),
             (.capture(gardeFranchie: _), .dureeMax):
            etat = .transcription
            // Le rotor est posé AVANT la clôture : celle-ci produit l'événement
            // suivant, dont l'état d'affichage doit pouvoir recouvrir le rotor
            // et non l'inverse.
            return [.desarmerMinuteries, .pastille(.transcription), .cloturerCapture]

        case (.transcription, .captureAnalysee(let sec)):
            // Whisper hallucine sur le silence : ne pas l'appeler est la seule parade.
            if sec < Self.secondesParoleMinimum { etat = .repos; return [.pastille(.annule)] }
            return [.envoyerAuWorker]

        case (.transcription, .texteRecu(let t)):
            etat = .repos
            let propre = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return propre.isEmpty ? [.pastille(.annule)] : [.coller(propre), .pastille(.succes)]

        case (.transcription, .echec(let m)):
            etat = .repos
            return [.pastille(.erreur(m))]

        default:
            return []
        }
    }
}

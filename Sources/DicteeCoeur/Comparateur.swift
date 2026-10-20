import Foundation

public struct ResultatComparaison {
    public let modele: ModeleLocal
    public let reponse: Transcripteur.Reponse?
    public let erreur: String?
    public var texte: String { reponse?.texte ?? "" }
}

/// Réutilise le protocole testé du transcripteur, ses délais et son mode hors ligne.
/// Les modèles sont chargés successivement ; le réglage persistant reste intact.
public final class Comparateur {
    private let transcripteur: Transcripteur
    public init(transcripteur: Transcripteur) { self.transcripteur = transcripteur }

    public func comparer(_ wav: URL, restaurer: ModeleLocal,
                         progression: @escaping (ModeleLocal) -> Void,
                         termine: @escaping ([ResultatComparaison]) -> Void) {
        transcripteur.finCapture()
        suivant(wav, restaurer: restaurer, resultats: [], progression: progression, termine: termine)
    }

    private func suivant(_ wav: URL, restaurer: ModeleLocal, resultats: [ResultatComparaison],
                         progression: @escaping (ModeleLocal) -> Void,
                         termine: @escaping ([ResultatComparaison]) -> Void) {
        guard resultats.count < ModeleLocal.allCases.count else {
            do { try transcripteur.changerModele(restaurer) }
            catch { transcripteur.surJournal?("restauration du modèle impossible : \(error)") }
            termine(resultats)
            return
        }
        let modele = ModeleLocal.allCases[resultats.count]
        progression(modele)
        do { try transcripteur.changerModele(modele) }
        catch {
            let resultat = ResultatComparaison(modele: modele, reponse: nil, erreur: String(describing: error))
            suivant(wav, restaurer: restaurer, resultats: resultats + [resultat], progression: progression, termine: termine)
            return
        }
        transcripteur.transcrire(wav) { [self] retour in
            let resultat: ResultatComparaison
            switch retour {
            case .success(let reponse): resultat = ResultatComparaison(modele: modele, reponse: reponse, erreur: nil)
            case .failure(let erreur): resultat = ResultatComparaison(modele: modele, reponse: nil, erreur: String(describing: erreur))
            }
            suivant(wav, restaurer: restaurer, resultats: resultats + [resultat], progression: progression, termine: termine)
        }
    }
}

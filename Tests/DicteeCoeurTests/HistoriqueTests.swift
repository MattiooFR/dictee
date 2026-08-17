import Testing
import Foundation
@testable import DicteeCoeur

private func dossierTemporaire() -> URL {
    let u = FileManager.default.temporaryDirectory
        .appendingPathComponent("dictee-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
private func jour(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_770_000_000 + Double(n) * 3600) }

@Test("une dictée ajoutée se relit à l'identique depuis le disque")
func allerRetour() throws {
    let f = dossierTemporaire().appendingPathComponent("h.jsonl")
    let h = Historique(fichier: f)
    let d = try h.ajouter(texte: "On publie demain.", secondes: 1.4, date: jour(0))

    let relu = Historique(fichier: f)
    relu.charger()
    #expect(relu.entrees.count == 1)
    #expect(relu.entrees[0].texte == "On publie demain.")
    #expect(relu.entrees[0].id == d.id)
    #expect(relu.entrees[0].secondes == 1.4)
}

@Test("les entrées sont rendues du plus récent au plus ancien")
func ordreAntichronologique() throws {
    let f = dossierTemporaire().appendingPathComponent("h.jsonl")
    let h = Historique(fichier: f)
    try h.ajouter(texte: "vieille", secondes: 1, date: jour(0))
    try h.ajouter(texte: "récente", secondes: 1, date: jour(5))
    #expect(h.entrees.map(\.texte) == ["récente", "vieille"])

    let relu = Historique(fichier: f); relu.charger()
    #expect(relu.entrees.map(\.texte) == ["récente", "vieille"])
}

@Test("une ligne corrompue est ignorée sans empêcher le chargement du reste")
func ligneCorrompue() throws {
    let f = dossierTemporaire().appendingPathComponent("h.jsonl")
    let h = Historique(fichier: f)
    try h.ajouter(texte: "avant", secondes: 1, date: jour(0))
    let brut = try String(contentsOf: f, encoding: .utf8) + "{ceci n'est pas du JSON\n"
    try brut.write(to: f, atomically: true, encoding: .utf8)

    let relu = Historique(fichier: f)
    var avertissement: String?
    relu.surJournal = { avertissement = $0 }
    relu.charger()
    #expect(relu.entrees.count == 1)
    #expect(relu.entrees[0].texte == "avant")
    #expect(avertissement?.contains("illisible") == true)
}

@Test("un fichier absent donne un historique vide, sans erreur")
func fichierAbsent() {
    let h = Historique(fichier: dossierTemporaire().appendingPathComponent("rien.jsonl"))
    h.charger()
    #expect(h.entrees.isEmpty)
}

@Test("la suppression retire l'entrée en mémoire et sur le disque")
func suppression() throws {
    let f = dossierTemporaire().appendingPathComponent("h.jsonl")
    let h = Historique(fichier: f)
    let a = try h.ajouter(texte: "à garder", secondes: 1, date: jour(0))
    let b = try h.ajouter(texte: "à jeter", secondes: 1, date: jour(1))

    try h.supprimer(id: b.id)
    #expect(h.entrees.map(\.id) == [a.id])

    let relu = Historique(fichier: f); relu.charger()
    #expect(relu.entrees.map(\.texte) == ["à garder"])
}

@Test("supprimer un identifiant inconnu ne change rien")
func suppressionInconnue() throws {
    let f = dossierTemporaire().appendingPathComponent("h.jsonl")
    let h = Historique(fichier: f)
    try h.ajouter(texte: "seule", secondes: 1, date: jour(0))
    try h.supprimer(id: "inexistant")
    #expect(h.entrees.count == 1)
}

@Test("la recherche ignore la casse et les accents")
func rechercheInsensible() throws {
    let f = dossierTemporaire().appendingPathComponent("h.jsonl")
    let h = Historique(fichier: f)
    try h.ajouter(texte: "Il faudra vérifier l'indexation", secondes: 1, date: jour(0))
    try h.ajouter(texte: "Relance le client", secondes: 1, date: jour(1))

    #expect(h.rechercher("VERIFIER").count == 1)
    #expect(h.rechercher("indexation").count == 1)
    #expect(h.rechercher("relance").count == 1)
    #expect(h.rechercher("introuvable").isEmpty)
}

@Test("une recherche vide ou blanche rend tout l'historique")
func rechercheVide() throws {
    let f = dossierTemporaire().appendingPathComponent("h.jsonl")
    let h = Historique(fichier: f)
    try h.ajouter(texte: "une", secondes: 1, date: jour(0))
    try h.ajouter(texte: "deux", secondes: 1, date: jour(1))
    #expect(h.rechercher("").count == 2)
    #expect(h.rechercher("   ").count == 2)
}

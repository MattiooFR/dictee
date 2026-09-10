import Foundation
import Testing
@testable import DicteeCoeur

@Test("les captures à réessayer survivent à une nouvelle instance et expirent")
func retentionAudio() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let attente = AudioEnAttente(dossier: root, retention: 60)
    let wav = try attente.ajouter([0, 0.5, -0.5])
    #expect(try Data(contentsOf: wav).count == 50)
    let recharge = AudioEnAttente(dossier: root, retention: 60)
    #expect(recharge.fichiers == [wav])
    try recharge.nettoyer(maintenant: Date().addingTimeInterval(61), sauf: wav)
    #expect(recharge.fichiers.count == 1)
    try recharge.nettoyer(maintenant: Date().addingTimeInterval(61))
    #expect(recharge.fichiers.isEmpty)
}

@Test("une dictée réussie peut être supprimée sans toucher aux autres")
func suppressionAudio() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let attente = AudioEnAttente(dossier: root)
    let a = try attente.ajouter([0.2]), b = try attente.ajouter([0.3])
    try attente.supprimer(a)
    #expect(attente.fichiers == [b])
    let permissions = try FileManager.default.attributesOfItem(atPath: b.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
}

@Test("un fichier de réglages partiel conserve des valeurs sûres")
func configurationPartielle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(#"{"toujoursPret":true,"inactiviteSecondes":-12,"cacheMo":-1}"#.utf8).write(to: root)
    let c = Configuration.charger(root)
    #expect(c.toujoursPret)
    #expect(c.inactiviteSecondes >= 180)
    #expect(c.cacheMo >= 64)
}

@Test("vider le tampon transfère les échantillons et libère la capture précédente")
func transfertTampon() {
    var t = TamponAudio()
    t.ajouter([0.1, 0.2])
    let audio = t.vider()
    #expect(audio == [0.1, 0.2])
    #expect(t.vider().isEmpty)
    t.ajouter([0.3])
    #expect(t.vider() == [0.3])
    #expect(audio == [0.1, 0.2])
}

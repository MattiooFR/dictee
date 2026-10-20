import Testing
import Foundation
@testable import DicteeCoeur

private func dossier() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dictee-test-\(UUID().uuidString)")
}
private func wav(_ dans: URL) throws -> URL {
    try FileManager.default.createDirectory(at: dans, withIntermediateDirectories: true)
    let u = dans.appendingPathComponent(UUID().uuidString + ".wav")
    try AudioWAV.wav([0, 0.5, -0.5]).write(to: u)
    return u
}

@Test("un audio rangé se retrouve par l'identifiant de sa dictée")
func rangerPuisRetrouver() throws {
    let racine = dossier()
    let archive = ArchiveAudio(dossier: racine.appendingPathComponent("audios"))
    let source = try wav(racine.appendingPathComponent("a-reessayer"))
    let cible = try archive.ranger(source, id: "ab12cd34")
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(archive.fichier("ab12cd34") == cible)
    #expect(archive.fichier("inconnu") == nil)
    try archive.supprimer("ab12cd34")
    #expect(archive.fichier("ab12cd34") == nil)
}

@Test("un identifiant ne peut pas faire sortir l'audio de son dossier")
func identifiantAssaini() throws {
    let racine = dossier()
    let archive = ArchiveAudio(dossier: racine.appendingPathComponent("audios"))
    let cible = try archive.ranger(try wav(racine), id: "../../evil")
    #expect(cible.deletingLastPathComponent().lastPathComponent == "audios")
}

@Test("les audios expirent après la rétention, pas avant")
func expiration() throws {
    let racine = dossier()
    let archive = ArchiveAudio(dossier: racine.appendingPathComponent("audios"), retention: 7 * 86400)
    try archive.ranger(try wav(racine), id: "recent")
    try archive.nettoyer(maintenant: Date().addingTimeInterval(6 * 86400))
    #expect(archive.fichier("recent") != nil)
    try archive.nettoyer(maintenant: Date().addingTimeInterval(7 * 86400 + 1))
    #expect(archive.fichier("recent") == nil)
}

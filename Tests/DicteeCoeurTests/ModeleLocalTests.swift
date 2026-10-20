import Foundation
import Testing
@testable import DicteeCoeur

@Test("le choix du moteur survit au redémarrage, les anciennes configs gardent Whisper")
func persistanceModele() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(Configuration.charger(url).modele == .whisper)
    var config = Configuration()
    config.modele = .cohere
    try config.enregistrer(url)
    #expect(Configuration.charger(url).modele == .cohere)
    try Data(#"{"modele":"inconnu"}"#.utf8).write(to: url)
    #expect(Configuration.charger(url).modele == .whisper)
}

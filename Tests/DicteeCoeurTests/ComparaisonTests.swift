import AppKit
import Foundation
import Testing
@testable import DicteeCoeur

@Test("terminer une comparaison ne colle pas les transcriptions")
func finComparaisonSansCollage() {
    var machine = MachineEtats()
    _ = machine.recevoir(.reessayer)
    #expect(machine.recevoir(.comparaisonTerminee) == [.pastille(.succes)])
    #expect(machine.etat == .repos)
}

@Test("la comparaison enchaîne les modèles et restaure le choix initial")
func comparaisonSuccessive() async throws {
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/faux-worker.py")
    let t = Transcripteur(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path, "modele"])
    defer { t.arreter() }
    let resultats: [ResultatComparaison] = await withCheckedContinuation { suite in
        Comparateur(transcripteur: t).comparer(URL(fileURLWithPath: "/tmp/test.wav"), restaurer: .parakeet,
                                             progression: { _ in }) { suite.resume(returning: $0) }
    }
    #expect(resultats.map(\.modele) == ModeleLocal.allCases)
    #expect(resultats.map(\.texte) == ["whisper", "parakeet", "cohere"])
    let texte: String = await withCheckedContinuation { suite in
        t.transcrire(URL(fileURLWithPath: "/tmp/test.wav")) { suite.resume(returning: (try? $0.get().texte) ?? "") }
    }
    #expect(texte == "parakeet")
}

@Test("le menu permet d'activer et de désactiver le mode comparaison")
@MainActor func menuComparaison() {
    _ = NSApplication.shared
    let c = Coordinateur(racine: URL(fileURLWithPath: "/tmp/dictee-test"))
    let menu = NSMenu(); menu.autoenablesItems = false
    c.menuNeedsUpdate(menu)
    let titre = "Mode comparaison (3 modèles)"
    #expect(menu.item(withTitle: titre)?.state == .off)
    #expect(menu.item(withTitle: titre)?.isEnabled == true)
    menu.performActionForItem(at: menu.indexOfItem(withTitle: titre))
    c.menuNeedsUpdate(menu)
    #expect(menu.item(withTitle: titre)?.state == .on)
    menu.performActionForItem(at: menu.indexOfItem(withTitle: titre))
    c.menuNeedsUpdate(menu)
    #expect(menu.item(withTitle: titre)?.state == .off)
}

@Test("comparaison réelle d'un WAV avec les trois moteurs", .enabled(if: ProcessInfo.processInfo.environment["DICTEE_TEST_MODELE"] == "1"))
func comparaisonReelle() async throws {
    let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let t = Transcripteur(executable: racine.appendingPathComponent(".venv/bin/python"), arguments: [racine.appendingPathComponent("worker/transcribe.py").path])
    defer { t.arreter() }
    let resultats: [ResultatComparaison] = await withCheckedContinuation { suite in
        Comparateur(transcripteur: t).comparer(racine.appendingPathComponent("worker/tests/fixtures/parole.wav"), restaurer: .whisper,
                                             progression: { _ in }) { suite.resume(returning: $0) }
    }
    #expect(resultats.count == 3)
    for r in resultats {
        #expect(r.erreur == nil)
        #expect(r.texte.lowercased().contains("bonjour"))
        #expect((r.reponse?.memoireMio ?? 0) > 100)
        #expect((r.reponse?.demarrageSecondes ?? 0) > 0)
    }
}

@Test("une erreur sur un modèle laisse les autres comparaisons se terminer")
func comparaisonAvecErreur() async throws {
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/faux-worker.py")
    let t = Transcripteur(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path, "erreur_parakeet"])
    defer { t.arreter() }
    let resultats: [ResultatComparaison] = await withCheckedContinuation { suite in
        Comparateur(transcripteur: t).comparer(URL(fileURLWithPath: "/tmp/test.wav"), restaurer: .whisper,
                                             progression: { _ in }) { suite.resume(returning: $0) }
    }
    #expect(resultats.count == 3)
    #expect(resultats[0].reponse != nil)
    #expect(resultats[1].erreur != nil)
    #expect(resultats[2].reponse != nil)
}

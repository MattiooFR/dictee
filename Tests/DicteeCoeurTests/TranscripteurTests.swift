import Testing
import Foundation
@testable import DicteeCoeur

private func fauxWorker(_ mode: String, delai: TimeInterval = 30) -> Transcripteur {
    let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/faux-worker.py")
    return Transcripteur(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                         arguments: [script.path, mode], delai: delai)
}

private func resultat(_ t: Transcripteur, _ chemin: String = "/tmp/a.wav")
    async -> Result<Transcripteur.Reponse, ErreurTranscription> {
    await withCheckedContinuation { c in
        t.transcrire(URL(fileURLWithPath: chemin)) { c.resume(returning: $0) }
    }
}

@Test("le worker répond un texte")
func repondTexte() async throws {
    let t = fauxWorker("ok"); try t.demarrer(); defer { t.arreter() }
    #expect(try await resultat(t).get().texte == "bonjour a.wav")
}

@Test("une erreur du worker remonte telle quelle")
func remonteErreur() async throws {
    let t = fauxWorker("erreur"); try t.demarrer(); defer { t.arreter() }
    guard case .failure(let e) = await resultat(t) else { Issue.record("attendu un échec"); return }
    #expect(e == .worker("micro cassé"))
}

@Test("un worker qui meurt ne laisse pas l'appel en suspens")
func workerMort() async throws {
    let t = fauxWorker("meurt"); try t.demarrer(); defer { t.arreter() }
    guard case .failure(let e) = await resultat(t) else { Issue.record("attendu un échec"); return }
    #expect(e == .workerMort)
}

@Test("un worker trop lent déclenche le délai dépassé")
func delaiDepasse() async throws {
    let t = fauxWorker("lent", delai: 0.4); try t.demarrer(); defer { t.arreter() }
    guard case .failure(let e) = await resultat(t) else { Issue.record("attendu un échec"); return }
    #expect(e == .delaiDepasse)
}

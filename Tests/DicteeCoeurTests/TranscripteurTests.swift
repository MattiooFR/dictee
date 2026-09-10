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

@Test("une demande démarre le worker absent sans perdre la dictée")
func demarrageADemande() async throws {
    let t = fauxWorker("ok"); defer { t.arreter() }
    #expect(try await resultat(t).get().texte == "bonjour a.wav")
}

@Test("une réponse ancienne ne peut pas remplacer la réponse courante")
func reponsePerimeeIgnoree() async throws {
    let t = fauxWorker("perime"); try t.demarrer(); defer { t.arreter() }
    #expect(try await resultat(t, "/tmp/nouvelle.wav").get().texte == "bonjour nouvelle.wav")
}

@Test("le worker est relancé à la demande après un timeout")
func repriseApresTimeout() async throws {
    let t = fauxWorker("lent_chemin", delai: 0.4); try t.demarrer(); defer { t.arreter() }
    guard case .failure(.delaiDepasse) = await resultat(t, "/tmp/lent.wav") else {
        Issue.record("timeout attendu"); return
    }
    #expect(try await resultat(t, "/tmp/rapide.wav").get().texte == "bonjour rapide.wav")
}

@Test("le chargement initial ne consomme pas le timeout de transcription")
func attentePreparationSeparee() async throws {
    let t = fauxWorker("demarrage_lent", delai: 0.4); defer { t.arreter() }
    #expect(try await resultat(t).get().texte == "bonjour a.wav")
}

@Test("une dictée attend la fin du réveil puis utilise son propre délai")
func attenteReveil() async throws {
    let t = fauxWorker("warmup_lent", delai: 0.4); defer { t.arreter() }
    _ = try await resultat(t).get()
    t.preparer()
    #expect(try await resultat(t).get().texte == "bonjour a.wav")
    t.finCapture()
}

@Test("la veille libère le worker et une nouvelle demande le redémarre")
func veillePuisReprise() async throws {
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/faux-worker.py")
    let t = Transcripteur(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                         arguments: [script.path, "ok"], inactivite: 0.15, purgeApres: 0.05)
    defer { t.arreter() }
    _ = try await resultat(t).get()
    try await Task.sleep(for: .milliseconds(350))
    #expect(!t.pret)
    #expect(try await resultat(t).get().texte == "bonjour a.wav")
}

@Test("le modèle ne se met pas en veille pendant une capture")
func pasDeVeillePendantCapture() async throws {
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/faux-worker.py")
    let t = Transcripteur(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                         arguments: [script.path, "ok"], inactivite: 0.15, purgeApres: 0.05)
    defer { t.arreter() }
    t.preparer()
    try await Task.sleep(for: .milliseconds(400))
    #expect(t.pret)
    t.finCapture()
    try await Task.sleep(for: .milliseconds(350))
    #expect(!t.pret)
}

@Test("chaîne Swift → Python → modèle local, purge puis reprise", .enabled(if: ProcessInfo.processInfo.environment["DICTEE_TEST_MODELE"] == "1"))
func vraiModeleLocal() async throws {
    let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let t = Transcripteur(executable: racine.appendingPathComponent(".venv/bin/python"),
                         arguments: [racine.appendingPathComponent("worker/transcribe.py").path],
                         inactivite: 0.7, purgeApres: 0.15)
    t.surJournal = { print($0) }
    defer { t.arreter() }
    let wav = racine.appendingPathComponent("worker/tests/fixtures/parole.wav").path
    let a = try await resultat(t, wav).get()
    #expect(a.texte.lowercased().contains("bonjour"))
    try await Task.sleep(for: .milliseconds(1000))
    #expect(!t.pret)
    t.preparer()
    let b = try await resultat(t, wav).get()
    #expect(b.texte.lowercased().contains("bonjour"))
    t.finCapture()
}

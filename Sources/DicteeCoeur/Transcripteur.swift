import Foundation
import Darwin

public enum ErreurTranscription: Error, Equatable {
    case workerMort, delaiDepasse, reponseIllisible, occupe
    case worker(String)
}

/// Toute la vie du processus et des demandes est confinée sur `file`.
/// Les générations isolent les anciens pipes/processus après un redémarrage.
public final class Transcripteur {
    public struct Reponse: Equatable {
        public let texte: String
        public let secondes: Double
    }
    private struct Demande {
        let id: String
        let wav: URL
        let debut: TimeInterval
        let fini: (Result<Reponse, ErreurTranscription>) -> Void
    }
    private let executable: URL
    private let arguments: [String]
    private let delai: TimeInterval
    private let delaiPreparation: TimeInterval
    private var inactivite: TimeInterval
    private let purgeApres: TimeInterval
    private let cacheMo: Int
    private let file = DispatchQueue(label: "dictee.transcripteur")
    private var process: Process?
    private var sortie: FileHandle?
    private var entree: FileHandle?
    private var tampon = Data()
    private var generation = UUID()
    private var generationRepos = UUID()
    private var disponible = false
    private var capture = false
    private var chauffe: String?
    private var demande: Demande?
    private var envoyee = false
    private var minuteur: DispatchWorkItem?
    private var dernierUsage = ProcessInfo.processInfo.systemUptime

    public var pret: Bool { file.sync { disponible && chauffe == nil } }
    public var surJournal: ((String) -> Void)?
    /// `true` = modèle en préparation, `false` = transcription réellement envoyée.
    public var surPreparation: ((Bool) -> Void)?

    public init(executable: URL, arguments: [String], delai: TimeInterval = 30,
                delaiPreparation: TimeInterval = 120, inactivite: TimeInterval = 900,
                purgeApres: TimeInterval = 60, cacheMo: Int = 512) {
        self.executable = executable; self.arguments = arguments; self.delai = delai
        self.delaiPreparation = delaiPreparation; self.inactivite = inactivite
        self.purgeApres = purgeApres; self.cacheMo = cacheMo
    }

    public func demarrer() throws { try file.sync { try lancer() } }

    private func journal(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.surJournal?(message) }
    }

    private func preparation(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in self?.surPreparation?(active) }
    }

    private func lancer() throws {
        guard process == nil else { return }
        let p = Process(), input = Pipe(), output = Pipe()
        let g = UUID(); generation = g
        p.executableURL = executable; p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"
        env["DICTEE_CACHE_MB"] = String(cacheMo)
        p.environment = env
        p.standardInput = input; p.standardOutput = output
        p.standardError = FileHandle.standardError
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            self?.file.async { [weak self] in
                guard let self, generation == g else { return }
                avaler(data)
            }
        }
        p.terminationHandler = { [weak self] _ in
            self?.file.async { [weak self] in
                guard let self, generation == g else { return }
                echouer(.workerMort)
            }
        }
        do { try p.run() }
        catch { output.fileHandleForReading.readabilityHandler = nil; throw error }
        process = p; entree = input.fileHandleForWriting; sortie = output.fileHandleForReading
        disponible = false
        armer(delaiPreparation)
        journal("moteur : démarrage local")
    }

    /// Appelé après la garde d'appui ou immédiatement au clic verrouillé.
    public func preparer() {
        file.async { [self] in
            capture = true; generationRepos = UUID()
            guard demande == nil, chauffe == nil else { return }
            journal(String(format: "réveil : %.1f s depuis le dernier usage",
                           ProcessInfo.processInfo.systemUptime - dernierUsage))
            do {
                if process == nil { try lancer() }
                else if disponible {
                    chauffe = UUID().uuidString
                    armer(delaiPreparation)
                    try envoyer(["id": chauffe!, "cmd": "warmup"])
                }
            } catch { echouer(.worker(error.localizedDescription)) }
        }
    }

    public func configurerVeille(_ secondes: TimeInterval) {
        file.async { [self] in
            inactivite = secondes
            if secondes == 0 && process == nil {
                do { try lancer() } catch { echouer(.worker(error.localizedDescription)) }
            }
            repos()
        }
    }

    public func finCapture() {
        file.async { [self] in capture = false; repos() }
    }

    public func transcrire(_ wav: URL,
                           _ fini: @escaping (Result<Reponse, ErreurTranscription>) -> Void) {
        file.async { [self] in
            guard demande == nil else {
                DispatchQueue.main.async { fini(.failure(.occupe)) }; return
            }
            generationRepos = UUID()
            demande = Demande(id: UUID().uuidString, wav: wav,
                              debut: ProcessInfo.processInfo.systemUptime, fini: fini)
            envoyee = false
            preparation(!disponible || chauffe != nil)
            do { try lancer(); try envoyerSiPret() }
            catch { echouer(.worker(error.localizedDescription)) }
        }
    }

    private func envoyerSiPret() throws {
        guard disponible, chauffe == nil, let d = demande, !envoyee else { return }
        envoyee = true
        preparation(false)
        journal(String(format: "demande %@ : attente moteur %.3f s", d.id,
                       ProcessInfo.processInfo.systemUptime - d.debut))
        armer(delai)
        try envoyer(["id": d.id, "cmd": "transcribe", "path": d.wav.path])
    }

    private func envoyer(_ obj: [String: Any]) throws {
        guard let entree else { throw ErreurTranscription.workerMort }
        var data = try JSONSerialization.data(withJSONObject: obj)
        data.append(0x0A)
        try entree.write(contentsOf: data)
    }

    private func avaler(_ data: Data) {
        tampon.append(data)
        guard tampon.count < 2_000_000 else { echouer(.reponseIllisible); return }
        while let i = tampon.firstIndex(of: 0x0A) {
            let ligne = Data(tampon[..<i])
            tampon.removeSubrange(...i)
            traiter(ligne)
        }
    }

    private func traiter(_ ligne: Data) {
        guard let o = try? JSONSerialization.jsonObject(with: ligne) as? [String: Any] else {
            echouer(.reponseIllisible); return
        }
        if let fatal = o["fatal"] as? String { echouer(.worker(fatal)); return }
        if let metrics = o["metrics"], let d = try? JSONSerialization.data(withJSONObject: metrics, options: .sortedKeys),
           let texte = String(data: d, encoding: .utf8) { journal("moteur métriques : \(texte)") }
        if o["ready"] as? Bool == true {
            disponible = true; minuteur?.cancel(); minuteur = nil
            journal("worker prêt")
            do { try envoyerSiPret() } catch { echouer(.workerMort) }
            repos(); return
        }
        guard let id = o["id"] as? String else { echouer(.reponseIllisible); return }
        if id == chauffe {
            if let erreur = o["error"] as? String { echouer(.worker(erreur)); return }
            guard o["done"] as? String == "warmup" else { echouer(.reponseIllisible); return }
            chauffe = nil; minuteur?.cancel(); minuteur = nil
            do { try envoyerSiPret() } catch { echouer(.workerMort) }
            repos(); return
        }
        guard let d = demande, d.id == id else { return } // réponse périmée / purge
        if let erreur = o["error"] as? String { conclure(.failure(.worker(erreur))); return }
        guard let texte = o["text"] as? String else { echouer(.reponseIllisible); return }
        journal(String(format: "demande %@ : total worker %.3f s", id,
                       ProcessInfo.processInfo.systemUptime - d.debut))
        conclure(.success(Reponse(texte: texte, secondes: o["sec"] as? Double ?? 0)))
    }

    private func armer(_ secondes: TimeInterval) {
        minuteur?.cancel()
        let g = generation
        let t = DispatchWorkItem { [weak self] in
            guard let self, generation == g else { return }
            echouer(.delaiDepasse)
        }
        minuteur = t
        file.asyncAfter(deadline: .now() + secondes, execute: t)
    }

    private func conclure(_ resultat: Result<Reponse, ErreurTranscription>) {
        minuteur?.cancel(); minuteur = nil
        let d = demande; demande = nil; envoyee = false
        if let d { DispatchQueue.main.async { d.fini(resultat) } }
        repos()
    }

    private func echouer(_ erreur: ErreurTranscription) {
        journal("moteur : \(erreur)")
        terminerProcessus(force: true)
        conclure(.failure(erreur))
    }

    private func repos() {
        guard !capture, demande == nil, chauffe == nil, disponible else { return }
        dernierUsage = ProcessInfo.processInfo.systemUptime
        let g = UUID(); generationRepos = g
        file.asyncAfter(deadline: .now() + purgeApres) { [weak self] in
            guard let self, generationRepos == g, disponible else { return }
            do { try envoyer(["id": UUID().uuidString, "cmd": "purge"]); journal("cache MLX purgé au repos") }
            catch { echouer(.workerMort) }
        }
        guard inactivite > 0 else { return } // Toujours prêt
        file.asyncAfter(deadline: .now() + inactivite) { [weak self] in
            guard let self, generationRepos == g else { return }
            terminerProcessus()
            journal("moteur arrêté après inactivité ; réveil au prochain appui")
        }
    }

    private func terminerProcessus(force: Bool = false) {
        generation = UUID(); generationRepos = UUID()
        minuteur?.cancel(); minuteur = nil
        sortie?.readabilityHandler = nil
        try? sortie?.close(); try? entree?.close()
        sortie = nil; entree = nil
        if let p = process, p.isRunning {
            p.terminationHandler = nil
            // Au repos, EOF laisse Python fermer proprement ses ressources.
            // Un worker bloqué reçoit SIGTERM puis SIGKILL si nécessaire.
            if force { p.terminate() }
            file.asyncAfter(deadline: .now() + (force ? 1 : 3)) {
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
        process = nil; disponible = false; chauffe = nil; tampon.removeAll()
    }

    public func arreter() {
        file.sync { terminerProcessus(); conclure(.failure(.workerMort)) }
    }
}

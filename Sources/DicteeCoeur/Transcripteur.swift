import Foundation

public enum ErreurTranscription: Error, Equatable {
    case workerMort, delaiDepasse, reponseIllisible
    case worker(String)
}

/// Pilote le process Python résident. Un travail à la fois.
/// Toute la mutation d'état passe par `file` : les rappels de `Process`
/// arrivent sur des threads arbitraires.
public final class Transcripteur {
    public struct Reponse: Equatable {
        public let texte: String
        public let secondes: Double
    }

    private let executable: URL
    private let arguments: [String]
    private let delai: TimeInterval
    private let file = DispatchQueue(label: "dictee.transcripteur")

    private var process: Process?
    private var versWorker: FileHandle?
    private var tampon = Data()
    private var attente: ((Result<Reponse, ErreurTranscription>) -> Void)?
    private var minuteur: DispatchWorkItem?

    public private(set) var pret = false
    public var surJournal: ((String) -> Void)?

    public init(executable: URL, arguments: [String], delai: TimeInterval = 30) {
        self.executable = executable
        self.arguments = arguments
        self.delai = delai
    }

    public func demarrer() throws {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        let entree = Pipe(), sortie = Pipe()
        p.standardInput = entree
        p.standardOutput = sortie
        p.standardError = FileHandle.standardError
        sortie.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            self?.file.async { self?.avaler(d) }
        }
        p.terminationHandler = { [weak self] _ in
            self?.file.async { self?.conclureMort() }
        }
        try p.run()
        process = p
        versWorker = entree.fileHandleForWriting
        pret = false
    }

    private func avaler(_ d: Data) {
        tampon.append(d)
        while let i = tampon.firstIndex(of: 0x0A) {
            let ligne = tampon[tampon.startIndex..<i]
            tampon = tampon[tampon.index(after: i)...]
            traiter(ligne)
        }
    }

    private func traiter(_ ligne: Data) {
        guard let o = try? JSONSerialization.jsonObject(with: ligne) as? [String: Any] else {
            conclure(.failure(.reponseIllisible)); return
        }
        if o["ready"] as? Bool == true {
            pret = true
            surJournal?("worker prêt")
            return
        }
        if let m = o["error"] as? String { conclure(.failure(.worker(m))); return }
        guard let t = o["text"] as? String else { conclure(.failure(.reponseIllisible)); return }
        conclure(.success(Reponse(texte: t, secondes: o["sec"] as? Double ?? 0)))
    }

    private func conclure(_ r: Result<Reponse, ErreurTranscription>) {
        minuteur?.cancel(); minuteur = nil
        guard let a = attente else { return }
        attente = nil
        DispatchQueue.main.async { a(r) }
    }

    private func conclureMort() {
        pret = false
        process = nil
        versWorker = nil
        tampon.removeAll()
        conclure(.failure(.workerMort))
    }

    public func transcrire(_ wav: URL,
                           _ fini: @escaping (Result<Reponse, ErreurTranscription>) -> Void) {
        file.async { [self] in
            guard let versWorker, process?.isRunning == true else {
                DispatchQueue.main.async { fini(.failure(.workerMort)) }
                return
            }
            attente = fini
            let travail = DispatchWorkItem { [weak self] in
                self?.file.async { self?.conclure(.failure(.delaiDepasse)) }
            }
            minuteur = travail
            file.asyncAfter(deadline: .now() + delai, execute: travail)
            versWorker.write(Data((wav.path + "\n").utf8))
        }
    }

    public func arreter() {
        file.sync { process?.terminate(); process = nil }
    }
}

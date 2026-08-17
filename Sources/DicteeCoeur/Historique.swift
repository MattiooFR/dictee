import Foundation

public struct Dictee: Equatable, Codable, Identifiable {
    public let id: String
    public let date: Date
    public let texte: String
    public let secondes: Double

    public init(id: String, date: Date, texte: String, secondes: Double) {
        self.id = id; self.date = date; self.texte = texte; self.secondes = secondes
    }
}

/// Archive des dictées, en JSONL. Ne connaît rien de l'interface.
/// Une ligne complète ou rien : une coupure en cours d'écriture ne peut
/// corrompre que la dernière ligne, et le chargement ignore l'illisible.
public final class Historique {
    private let fichier: URL
    /// Plus récent en premier.
    public private(set) var entrees: [Dictee] = []
    public var surJournal: ((String) -> Void)?

    public init(fichier: URL) { self.fichier = fichier }

    private static func encodeur() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private static func decodeur() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public func charger() {
        entrees = []
        guard let contenu = try? String(contentsOf: fichier, encoding: .utf8) else { return }
        let dec = Historique.decodeur()
        var ignorees = 0
        for ligne in contenu.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let d = try? dec.decode(Dictee.self, from: Data(ligne.utf8)) else {
                ignorees += 1; continue
            }
            entrees.append(d)
        }
        if ignorees > 0 { surJournal?("historique : \(ignorees) ligne(s) illisible(s) ignorée(s)") }
        entrees.sort { $0.date > $1.date }
    }

    @discardableResult
    public func ajouter(texte: String, secondes: Double, date: Date = Date()) throws -> Dictee {
        let d = Dictee(id: String(UUID().uuidString.prefix(8)).lowercased(),
                       date: date, texte: texte, secondes: secondes)
        var ligne = try Historique.encodeur().encode(d)
        ligne.append(0x0A)
        try ajouterAuFichier(ligne)
        entrees.insert(d, at: 0)
        return d
    }

    public func supprimer(id: String) throws {
        guard entrees.contains(where: { $0.id == id }) else { return }
        entrees.removeAll { $0.id == id }
        try reecrire()
    }

    /// Insensible à la casse et aux accents, comme les filtres du worker.
    public func rechercher(_ requete: String) -> [Dictee] {
        let q = Historique.normaliser(requete.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return entrees }
        return entrees.filter { Historique.normaliser($0.texte).contains(q) }
    }

    static func normaliser(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                  locale: Locale(identifier: "fr_FR"))
    }

    private func ajouterAuFichier(_ d: Data) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fichier.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fichier.path) {
            fm.createFile(atPath: fichier.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: fichier)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: d)
    }

    /// Réécriture complète via un temporaire : la suppression est rare et le
    /// fichier minuscule, mais elle ne doit jamais laisser un fichier à moitié écrit.
    private func reecrire() throws {
        let enc = Historique.encodeur()
        var d = Data()
        for e in entrees.reversed() { d.append(try enc.encode(e)); d.append(0x0A) }
        let temp = fichier.appendingPathExtension("tmp")
        try d.write(to: temp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: fichier.path) {
            _ = try fm.replaceItemAt(fichier, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: fichier)
        }
    }
}

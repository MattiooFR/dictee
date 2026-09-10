import Foundation

/// Audio en attente ou en échec : privé, conservé au plus 24 heures.
/// Le fichier est créé avant l'envoi au worker ; il survit donc à un crash.
public final class AudioEnAttente {
    private let dossier: URL
    private let retention: TimeInterval
    private let fm = FileManager.default
    public init(dossier: URL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/dictee/a-reessayer"), retention: TimeInterval = 86400) {
        self.dossier = dossier.resolvingSymlinksInPath(); self.retention = retention
    }
    public var fichiers: [URL] {
        ((try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "wav" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .map { $0.resolvingSymlinksInPath() }
            .sorted { date($0) > date($1) }
    }
    public func date(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    public func ajouter(_ echantillons: [Float]) throws -> URL {
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dossier.path)
        let url = dossier.appendingPathComponent(UUID().uuidString + ".wav")
        try AudioWAV.wav(echantillons).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url.resolvingSymlinksInPath()
    }
    public func supprimer(_ url: URL) throws {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath().path == dossier.resolvingSymlinksInPath().path else { return }
        try fm.removeItem(at: url)
    }
    public func nettoyer(maintenant: Date = Date(), sauf active: URL? = nil) throws {
        for url in fichiers where url.resolvingSymlinksInPath() != active?.resolvingSymlinksInPath() && maintenant.timeIntervalSince(date(url)) >= retention {
            try supprimer(url)
        }
    }
}

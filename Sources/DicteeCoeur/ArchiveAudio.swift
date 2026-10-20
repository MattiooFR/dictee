import Foundation

/// Audio des dictées réussies, rangé sous l'identifiant de la dictée pour
/// pouvoir le réécouter ou l'envoyer depuis l'historique. Privé, conservé
/// `retention` secondes (7 jours par défaut).
public final class ArchiveAudio {
    private let dossier: URL
    private let retention: TimeInterval
    private let fm = FileManager.default
    public init(dossier: URL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/dictee/audios"), retention: TimeInterval = 7 * 86400) {
        self.dossier = dossier.resolvingSymlinksInPath(); self.retention = retention
    }

    /// Déplace (sans copier) le WAV sous le nom `<id>.wav`.
    @discardableResult
    public func ranger(_ wav: URL, id: String) throws -> URL {
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dossier.path)
        let cible = url(id)
        if fm.fileExists(atPath: cible.path) { try fm.removeItem(at: cible) }
        try fm.moveItem(at: wav, to: cible)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cible.path)
        // Le déplacement garde la date de l'enregistrement : la rétention part du rangement.
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: cible.path)
        return cible
    }

    public func fichier(_ id: String) -> URL? {
        let u = url(id)
        return fm.fileExists(atPath: u.path) ? u : nil
    }

    public func supprimer(_ id: String) throws {
        guard let u = fichier(id) else { return }
        try fm.removeItem(at: u)
    }

    public func nettoyer(maintenant: Date = Date()) throws {
        let fichiers = (try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for u in fichiers where u.pathExtension == "wav" {
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if maintenant.timeIntervalSince(date) >= retention { try fm.removeItem(at: u) }
        }
    }

    /// L'identifiant vient de l'historique : on refuse tout ce qui pourrait sortir du dossier.
    private func url(_ id: String) -> URL {
        let sur = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return dossier.appendingPathComponent(sur + ".wav")
    }
}

import Foundation

public struct Configuration {
    public var toujoursPret = false
    public var inactiviteSecondes: Double = 900
    public var purgeSecondes: Double = 60
    public var cacheMo = 512
    public static var chemin: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/dictee/config.json")
    }

    public static func charger(_ url: URL = chemin) -> Configuration {
        var c = Configuration()
        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return c }
        c.toujoursPret = o["toujoursPret"] as? Bool ?? false
        if let n = o["inactiviteSecondes"] as? Double, n.isFinite, n >= 180 { c.inactiviteSecondes = n }
        if let n = o["purgeSecondes"] as? Double, n.isFinite, n >= 1 { c.purgeSecondes = n }
        if let n = o["cacheMo"] as? Int, (64...2048).contains(n) { c.cacheMo = n }
        return c
    }

    public func enregistrer(_ url: URL = chemin) throws {
        let o: [String: Any] = ["toujoursPret": toujoursPret, "inactiviteSecondes": inactiviteSecondes,
                                "purgeSecondes": purgeSecondes, "cacheMo": cacheMo]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}

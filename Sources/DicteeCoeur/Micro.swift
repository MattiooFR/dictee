import AVFoundation

/// Capture micro. Le moteur est préparé au lancement mais démarré uniquement
/// pendant une dictée : l'indicateur orange de macOS ne s'allume donc que
/// quand on parle vraiment.
public final class Micro {
    private let moteur = AVAudioEngine()
    private let file = DispatchQueue(label: "dictee.micro")
    private var echantillons: [Float] = []
    private var conv: Convertisseur?

    /// Appelé sur la file principale, ~46 fois par seconde pendant la capture.
    public var surNiveau: ((Float) -> Void)?

    public init() {}

    public func preparer() { moteur.prepare() }

    public func demarrer() throws {
        file.sync { echantillons.removeAll(keepingCapacity: true) }
        let entree = moteur.inputNode
        let format = entree.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw ErreurAudio.conversionImpossible }

        let convertisseur = try Convertisseur(depuis: format)
        conv = convertisseur
        entree.removeTap(onBus: 0)
        entree.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let self else { return }
            if let canaux = buf.floatChannelData {
                let db = AudioWAV.niveauDBFS(canaux[0], Int(buf.frameLength))
                DispatchQueue.main.async { self.surNiveau?(db) }
            }
            if let morceau = try? convertisseur.convertir(buf) {
                self.file.async { self.echantillons.append(contentsOf: morceau) }
            }
        }
        try moteur.start()
    }

    @discardableResult
    public func arreter() -> [Float] {
        moteur.stop()
        moteur.inputNode.removeTap(onBus: 0)
        conv = nil
        return file.sync { echantillons }
    }

    public func ecrireWAV(_ echantillons: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictee-\(UUID().uuidString.prefix(8)).wav")
        try AudioWAV.wav(echantillons).write(to: url)
        return url
    }
}

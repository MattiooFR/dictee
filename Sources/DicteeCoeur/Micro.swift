import AVFoundation

/// Capture micro. Le moteur est préparé au lancement mais démarré uniquement
/// pendant une dictée : l'indicateur orange de macOS ne s'allume donc que
/// quand on parle vraiment.
public final class Micro {
    private var moteur = AVAudioEngine()
    private let file = DispatchQueue(label: "dictee.micro")
    private var tampon = TamponAudio()
    private var conv: Convertisseur?
    private var erreursConversion = 0
    private var niveauxCanaux: [Float] = []

    /// Appelé sur la file principale, ~46 fois par seconde pendant la capture.
    public var surNiveau: ((Float) -> Void)?

    public init() {}

    public static func autorisationAccordee() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static func demanderAutorisation() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    /// Préalloue les ressources audio sans engager le micro.
    ///
    /// `prepare()` sur un moteur dont aucun nœud n'a été touché lève une
    /// exception Objective-C — que Swift ne peut PAS rattraper avec `try`, donc
    /// le process meurt. Accéder à `inputNode` attache le nœud au graphe et
    /// satisfait la précondition.
    public func preparer() {
        let entree = moteur.inputNode
        guard entree.inputFormat(forBus: 0).sampleRate > 0 else { return }
        moteur.prepare()
    }

    public func demarrer() throws {
        file.sync { _ = tampon.vider(); erreursConversion = 0; niveauxCanaux = [] }
        var entree = moteur.inputNode
        // Un appel peut exposer les capsules brutes du micro à un niveau
        // beaucoup plus faible. Demander le signal vocal traité à macOS,
        // avec son gain automatique, avant de choisir le format du tap.
        if !entree.isVoiceProcessingEnabled && entree.inputFormat(forBus: 0).channelCount > 2 {
            // prepare() a déjà initialisé l'unité matérielle. Le changement
            // de type d'unité nécessite un moteur neuf (-10849 sinon).
            moteur = AVAudioEngine()
            entree = moteur.inputNode
            do {
                try entree.setVoiceProcessingEnabled(true)
                entree.isVoiceProcessingAGCEnabled = true
                entree.voiceProcessingOtherAudioDuckingConfiguration = .init(
                    enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                moteur = AVAudioEngine()
                throw error
            }
        }
        let format = entree.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw ErreurAudio.conversionImpossible }

        let convertisseur = try Convertisseur(depuis: format)
        conv = convertisseur
        entree.removeTap(onBus: 0)
        entree.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let self else { return }
            if let canaux = buf.floatChannelData {
                let niveaux = (0..<Int(buf.format.channelCount)).map {
                    AudioWAV.niveauDBFS(canaux[$0], Int(buf.frameLength))
                }
                let db = niveaux.first ?? -60
                DispatchQueue.main.async { self.surNiveau?(db) }
                self.file.async {
                    if self.niveauxCanaux.count != niveaux.count { self.niveauxCanaux = niveaux }
                    else { self.niveauxCanaux = zip(self.niveauxCanaux, niveaux).map { max($0, $1) } }
                }
            }
            do {
                let morceau = try convertisseur.convertir(buf)
                self.file.async { self.tampon.ajouter(morceau) }
            } catch {
                self.file.async { self.erreursConversion += 1 }
            }
        }
        do { try moteur.start() }
        catch {
            entree.removeTap(onBus: 0)
            conv = nil
            moteur = AVAudioEngine()
            throw error
        }
        journaliser("micro : \(format.sampleRate) Hz, \(format.channelCount) canaux, traitement vocal : \(entree.isVoiceProcessingEnabled)")
    }

    @discardableResult
    public func arreter() -> [Float] {
        moteur.stop()
        moteur.inputNode.removeTap(onBus: 0)
        // Garder l'unité configurée entre deux appuis. La détruire ici
        // reconfigure le périphérique partagé et peut arrêter le moteur
        // d'une autre app. stop() suspend la capture et le traitement.
        conv = nil
        return file.sync {
            if erreursConversion > 0 { journaliser("micro : \(erreursConversion) erreurs de conversion") }
            journaliser("micro : niveaux RMS max par canal (dBFS) : \(niveauxCanaux.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
            return tampon.vider()
        }
    }

    public func ecrireWAV(_ echantillons: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictee-\(UUID().uuidString.prefix(8)).wav")
        try AudioWAV.wav(echantillons).write(to: url)
        return url
    }
}

/// Possession transférée à la clôture : le micro ne retient aucun ancien audio.
struct TamponAudio {
    private var echantillons: [Float] = []
    mutating func ajouter(_ morceau: [Float]) { echantillons.append(contentsOf: morceau) }
    mutating func vider() -> [Float] {
        let resultat = echantillons
        echantillons = []
        return resultat
    }
}

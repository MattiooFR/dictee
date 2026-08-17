import AVFoundation

public enum ErreurAudio: Error, Equatable { case conversionImpossible, conversion(String) }

/// Convertit un flux micro en Float32 mono 16 kHz.
/// Un convertisseur par capture : le rééchantillonnage est à état, en recréer
/// un à chaque trame produirait des artefacts aux jointures.
public final class Convertisseur {
    public static let tauxCible: Double = 16_000
    public static let formatCible = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                  sampleRate: tauxCible,
                                                  channels: 1, interleaved: false)!
    private let conv: AVAudioConverter?
    private let ratio: Double

    public init(depuis entree: AVAudioFormat) throws {
        if entree == Convertisseur.formatCible {
            conv = nil; ratio = 1
        } else {
            guard let c = AVAudioConverter(from: entree, to: Convertisseur.formatCible)
            else { throw ErreurAudio.conversionImpossible }
            conv = c
            ratio = Convertisseur.tauxCible / entree.sampleRate
        }
    }

    public func convertir(_ entree: AVAudioPCMBuffer) throws -> [Float] {
        guard let conv else {
            return Array(UnsafeBufferPointer(start: entree.floatChannelData![0],
                                             count: Int(entree.frameLength)))
        }
        let capacite = AVAudioFrameCount(Double(entree.frameLength) * ratio) + 256
        guard let sortie = AVAudioPCMBuffer(pcmFormat: Convertisseur.formatCible,
                                            frameCapacity: capacite)
        else { throw ErreurAudio.conversionImpossible }
        var fourni = false
        var err: NSError?
        conv.convert(to: sortie, error: &err) { _, statut in
            if fourni { statut.pointee = .noDataNow; return nil }
            fourni = true; statut.pointee = .haveData; return entree
        }
        if let err { throw ErreurAudio.conversion(err.localizedDescription) }
        return Array(UnsafeBufferPointer(start: sortie.floatChannelData![0],
                                         count: Int(sortie.frameLength)))
    }
}

public enum AudioWAV {
    public static let taux: UInt32 = 16_000
    public static let seuilParoleDBFS: Float = -45

    /// Sérialise des échantillons [-1,1] en WAV PCM 16 bits mono 16 kHz.
    public static func wav(_ e: [Float]) -> Data {
        var d = Data(capacity: 44 + e.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let octets = UInt32(e.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + octets)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(taux); u32(taux * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(octets)
        for v in e {
            let i = Int16(max(-1, min(1, v)) * 32767)
            withUnsafeBytes(of: i.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }

    /// Niveau RMS d'une trame, en dBFS, plancher à -60.
    public static func niveauDBFS(_ p: UnsafePointer<Float>, _ n: Int) -> Float {
        guard n > 0 else { return -60 }
        var s: Float = 0
        for i in 0..<n { s += p[i] * p[i] }
        let rms = (s / Float(n)).squareRoot()
        return rms > 0 ? max(-60, 20 * log10(rms)) : -60
    }

    /// Durée de signal au-dessus du seuil, mesurée par fenêtres de 20 ms.
    public static func secondesParlees(_ e: [Float]) -> Double {
        let fenetre = Int(taux) / 50
        guard e.count >= fenetre else { return 0 }
        var retenues = 0
        var i = 0
        while i + fenetre <= e.count {
            let db = e.withUnsafeBufferPointer { niveauDBFS($0.baseAddress! + i, fenetre) }
            if db > seuilParoleDBFS { retenues += 1 }
            i += fenetre
        }
        return Double(retenues) / 50.0
    }
}

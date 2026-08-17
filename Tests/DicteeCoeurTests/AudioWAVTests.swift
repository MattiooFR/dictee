import Testing
import AVFoundation
@testable import DicteeCoeur

private func format(_ taux: Double, _ canaux: AVAudioChannelCount) -> AVAudioFormat {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: taux,
                  channels: canaux, interleaved: false)!
}

private func trame(_ f: AVAudioFormat, _ n: AVAudioFrameCount,
                   amplitude: Float = 0.5, depart: Int = 0) -> AVAudioPCMBuffer {
    let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n)!
    b.frameLength = n
    for c in 0..<Int(f.channelCount) {
        for i in 0..<Int(n) {
            b.floatChannelData![c][i] =
                sin(2 * .pi * 440 * Float(depart + i) / Float(f.sampleRate)) * amplitude
        }
    }
    return b
}

@Test("un flux 48 kHz stéréo découpé en trames rend 16 kHz mono, durée préservée")
func fluxComplet() throws {
    let f = format(48_000, 2)
    let conv = try Convertisseur(depuis: f)
    var sortie: [Float] = []
    for k in 0..<47 { sortie += try conv.convertir(trame(f, 1024, depart: k * 1024)) }
    // 47 × 1024 trames à 48 kHz = 1,003 s → ~16 050 échantillons à 16 kHz
    #expect(abs(Double(sortie.count) - 16_050) < 300)
}

@Test("format déjà cible : passe-plat sans convertisseur")
func passePlat() throws {
    let f = Convertisseur.formatCible
    let conv = try Convertisseur(depuis: f)
    #expect(try conv.convertir(trame(f, 1600)).count == 1600)
}

@Test("l'en-tête WAV est conforme")
func enTete() {
    let d = AudioWAV.wav([Float](repeating: 0, count: 16_000))
    #expect(d.count == 44 + 32_000)
    #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
    #expect(String(decoding: d[8..<12], as: UTF8.self) == "WAVE")
    #expect(d[24] == 0x80 && d[25] == 0x3E)   // 16000 Hz little-endian
    #expect(d[34] == 16)                       // 16 bits par échantillon
}

@Test("le silence ne compte aucune seconde parlée, 1 s de signal en compte ~1")
func mesureParole() {
    #expect(AudioWAV.secondesParlees([Float](repeating: 0, count: 16_000)) == 0)
    let f = format(16_000, 1)
    let b = trame(f, 16_000)
    let e = Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: 16_000))
    #expect(abs(AudioWAV.secondesParlees(e) - 1.0) < 0.05)
}

@Test("un souffle très faible reste sous le seuil de parole")
func souffleFaible() {
    let f = format(16_000, 1)
    let b = trame(f, 16_000, amplitude: 0.001)   // ≈ -63 dBFS
    let e = Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: 16_000))
    #expect(AudioWAV.secondesParlees(e) == 0)
}

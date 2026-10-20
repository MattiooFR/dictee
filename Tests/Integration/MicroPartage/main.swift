// Test matériel explicite, à lancer depuis la racine du dépôt :
// swiftc Tests/Integration/MicroPartage/main.swift Sources/DicteeCoeur/AudioWAV.swift Sources/DicteeCoeur/Micro.swift -o /tmp/dictee-test-micro-partage
// /tmp/dictee-test-micro-partage
//
// Utilise le micro pendant environ 6 secondes, sans conserver ni transcrire
// le son. Simule un autre client Voice Processing (même API que FaceTime),
// vérifie deux captures, la survie de l'autre moteur, le retour après l'appel
// et l'absence de capture au repos. La reconnaissance d'une vraie phrase
// pendant FaceTime reste un test manuel distinct.

import AVFoundation
import Foundation
import CoreAudio
setbuf(stdout, nil)
func journaliser(_ texte: String) { print(texte) }
func capture(_ micro: Micro, _ label: String) throws {
    let start = Date()
    try micro.demarrer()
    print(label, "startup seconds", Date().timeIntervalSince(start))
    Thread.sleep(forTimeInterval: 2)
    let samples = micro.arreter()
    let peak = samples.map { abs($0) }.max() ?? 0
    print(label, "samples", samples.count, "peakDB", peak > 0 ? 20 * log10(peak) : -120)
    precondition(samples.count > 24000, "Capture missing or truncated")
}
let micro = Micro()
micro.preparer()
let other = AVAudioEngine()
try other.inputNode.setVoiceProcessingEnabled(true)
other.inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
other.inputNode.installTap(onBus: 0, bufferSize: 1024, format: other.inputNode.outputFormat(forBus: 0)) { _, _ in }
try other.start()
try capture(micro, "shared 1")
precondition(other.isRunning, "Other client stopped")
try capture(micro, "shared 2")
precondition(other.isRunning, "Other client stopped")
other.stop()
other.inputNode.removeTap(onBus: 0)
try other.inputNode.setVoiceProcessingEnabled(false)
Thread.sleep(forTimeInterval: 0.5)
try capture(micro, "after call")
print("PASS: repeated shared capture and return after call")

if #available(macOS 14.2, *) {
    var pid = getpid()
    var object = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout.size(ofValue: pid)), &pid, &size, &object)
    precondition(status == noErr)
    Thread.sleep(forTimeInterval: 0.3)
    address.mSelector = kAudioProcessPropertyIsRunningInput
    var active: UInt32 = 1
    size = 4
    precondition(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &active) == noErr)
    print("input active after stop:", active)
    precondition(active == 0, "Microphone still active at rest")
}

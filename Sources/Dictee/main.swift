import AppKit
import DicteeCoeur
import Foundation

let aide = """
Dictée \(Version.courante) — dictée vocale locale

  Dictee                      lance l'application (mode normal)
  Dictee --test-micro         enregistre 3 s et écrit un WAV
  Dictee --test-collage TEXTE colle TEXTE après 3 s
  Dictee --test-clavier       journalise les appuis sur ⌘ droite
  Dictee --test-pastille      fait défiler les états de la pastille
  Dictee --aide               affiche ce message
"""

switch CommandLine.arguments.dropFirst().first {
case "--aide", "-h":
    print(aide)

case "--test-micro":
    let micro = Micro()
    micro.preparer()
    micro.surNiveau = { db in
        let barres = Int(max(0, min(30, (db + 50) / 50 * 30)))
        print("\r[" + String(repeating: "█", count: barres)
              + String(repeating: " ", count: 30 - barres)
              + String(format: "] %6.1f dBFS", db), terminator: "")
        fflush(stdout)
    }
    print("Enregistrement 3 s — parle maintenant.")
    try micro.demarrer()
    Thread.sleep(forTimeInterval: 3)
    let echantillons = micro.arreter()
    let wav = try micro.ecrireWAV(echantillons)
    print("\n\(echantillons.count) échantillons, "
          + String(format: "%.2f s de parole", AudioWAV.secondesParlees(echantillons)))
    print("WAV : \(wav.path)")

case "--test-collage":
    let texte = CommandLine.arguments.dropFirst(2).first ?? "essai de collage Dictée"
    print("Passe dans l'app cible : collage dans 3 s…")
    Thread.sleep(forTimeInterval: 3)
    Collage.coller(texte)
    print("collé.")

case "--test-clavier":
    guard Declencheur.autorisationAccordee() else {
        print("Surveillance des entrées non accordée. Demande en cours…")
        Declencheur.demanderAutorisation()
        print("Accorde l'autorisation puis relance cette commande.")
        exit(1)
    }
    let d = Declencheur { signal in print("→ \(signal)") }
    try d.demarrer()
    print("Maintiens ⌘ droite. Teste aussi ⌘ droite + C. Ctrl-C pour arrêter.")
    CFRunLoopRun()

case "--test-pastille":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let p = Pastille()

    var phase = 0.0
    // .common et non .default : sinon le minuteur se fige pendant les animations.
    let faussesVoix = Timer(timeInterval: 1.0 / 46, repeats: true) { _ in
        phase += 0.14
        // parole simulée : alternance de syllabes et de blancs
        let enveloppe = max(0, sin(phase)) * (0.6 + 0.4 * sin(phase * 3.1))
        p.niveau(Float(-50 + 45 * enveloppe))
    }
    RunLoop.main.add(faussesVoix, forMode: .common)

    let scenario: [(TimeInterval, EtatPastille)] = [
        (1.0, .ecoute), (3.0, .transcription), (5.0, .succes),
        (6.5, .annule), (8.0, .erreur("worker injoignable")), (12.0, .repos),
    ]
    for (t, etat) in scenario {
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { p.afficher(etat) }
    }
    print("Défilé des états pendant 13 s. Ctrl-C pour arrêter plus tôt.")
    DispatchQueue.main.asyncAfter(deadline: .now() + 13) { app.terminate(nil) }
    app.run()

case .some(let inconnu):
    FileHandle.standardError.write(Data("sous-commande inconnue : \(inconnu)\n".utf8))
    print(aide)
    exit(2)
case nil:
    let racine = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["DICTEE_ROOT"]
        ?? FileManager.default.currentDirectoryPath)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // agent : pas d'icône dans le Dock
    let coordinateur = Coordinateur(racine: racine)
    do { try coordinateur.demarrer() }
    catch {
        FileHandle.standardError.write(Data("démarrage impossible : \(error)\n".utf8))
        exit(1)
    }
    app.run()
}

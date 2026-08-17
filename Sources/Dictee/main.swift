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

case .some(let inconnu):
    FileHandle.standardError.write(Data("sous-commande inconnue : \(inconnu)\n".utf8))
    print(aide)
    exit(2)
case nil:
    print("mode application : pas encore câblé (tâche 11)")
}

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
case .some(let inconnu):
    FileHandle.standardError.write(Data("sous-commande inconnue : \(inconnu)\n".utf8))
    print(aide)
    exit(2)
case nil:
    print("mode application : pas encore câblé (tâche 11)")
}

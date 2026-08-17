import AppKit
import CoreGraphics

public enum Collage {
    private static let toucheV: CGKeyCode = 9

    /// Écrit le texte dans le presse-papier et poste un ⌘V synthétique.
    /// Rien n'est restauré : le gestionnaire d'historique de presse-papier de
    /// l'utilisateur conserve l'entrée précédente et archive chaque dictée.
    public static func coller(_ texte: String) {
        let presse = NSPasteboard.general
        presse.clearContents()
        presse.setString(texte, forType: .string)
        frapperCommandeV()
    }

    /// Poste un ⌘V synthétique. Exposé pour que le recollage différé
    /// (après réactivation d'une autre application) puisse le déclencher seul.
    public static func frapperCommandeV() {
        // .privateState : les modificateurs physiquement enfoncés ne viennent
        // pas contaminer l'événement synthétique.
        guard let source = CGEventSource(stateID: .privateState),
              let bas = CGEvent(keyboardEventSource: source, virtualKey: toucheV, keyDown: true),
              let haut = CGEvent(keyboardEventSource: source, virtualKey: toucheV, keyDown: false)
        else { return }
        bas.flags = .maskCommand
        haut.flags = .maskCommand
        bas.post(tap: .cghidEventTap)
        usleep(10_000)   // certaines apps ratent un ⌘V posté d'un seul bloc
        haut.post(tap: .cghidEventTap)
    }
}

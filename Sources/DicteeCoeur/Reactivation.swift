import AppKit

public enum Reactivation {
    /// Copie le texte, réactive l'application cible, puis poste le ⌘V une fois
    /// qu'elle est vraiment au premier plan.
    ///
    /// L'attente n'est pas cosmétique : poster le ⌘V immédiatement après
    /// `activate()` le ferait arriver avant le basculement, donc dans le vide.
    public static func collerDans(_ app: NSRunningApplication?,
                                  texte: String,
                                  plafond: TimeInterval = 1.0,
                                  surJournal: ((String) -> Void)? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texte, forType: .string)

        guard let app else {
            surJournal?("aucune application cible : le texte reste dans le presse-papier")
            return
        }
        app.activate()
        attendre(app, depuis: Date(), plafond: plafond, surJournal: surJournal)
    }

    private static func attendre(_ app: NSRunningApplication, depuis: Date,
                                 plafond: TimeInterval,
                                 surJournal: ((String) -> Void)?) {
        let devant = NSWorkspace.shared.frontmostApplication?.processIdentifier
                  == app.processIdentifier
        let expire = Date().timeIntervalSince(depuis) > plafond

        if devant {
            // Une image de plus : l'application est devant, mais son champ de
            // saisie n'a pas forcément fini de reprendre le focus clavier.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Collage.frapperCommandeV()
            }
            return
        }
        if expire {
            surJournal?("l'application cible n'est pas revenue au premier plan "
                        + "— le texte reste dans le presse-papier")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            attendre(app, depuis: depuis, plafond: plafond, surJournal: surJournal)
        }
    }
}

import AppKit

/// Table qui remonte ⏎, ⌫ et Échap au lieu de les laisser au comportement
/// par défaut.
final class TableHistorique: NSTableView {
    var surEntree: ((Int) -> Void)?
    var surSuppression: ((Int) -> Void)?
    var surEchappement: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:                                    // ⏎ (retour et pavé)
            if selectedRow >= 0 { surEntree?(selectedRow) }
        case 51, 117:                                   // ⌫ et suppr avant
            if selectedRow >= 0 { surSuppression?(selectedRow) }
        case 53:                                        // Échap
            surEchappement?()
        default:
            super.keyDown(with: event)
        }
    }
}

/// Fenêtre de consultation des dictées. Ne colle rien elle-même : elle délègue
/// via `surRecoller`, pour rester ignorante du mécanisme de collage.
public final class FenetreHistorique: NSObject, NSTableViewDataSource,
                                      NSTableViewDelegate, NSSearchFieldDelegate {
    private let historique: Historique
    private var fenetre: NSWindow?
    private var table = TableHistorique()
    private var recherche = NSSearchField()
    private var affichees: [Dictee] = []
    /// Application au premier plan au moment de l'ouverture : c'est là que le
    /// texte devra retourner.
    private var appPrecedente: NSRunningApplication?

    public var surRecoller: ((String, NSRunningApplication?) -> Void)?

    public init(historique: Historique) {
        self.historique = historique
        super.init()
    }

    public func ouvrir() {
        appPrecedente = NSWorkspace.shared.frontmostApplication
        if fenetre == nil { construire() }
        rafraichir()
        // Un agent (LSUIElement) peut activer une fenêtre : c'est nécessaire
        // pour taper dans la recherche. macOS 14 déprécie `ignoringOtherApps`,
        // mais c'est la seule forme qui ramène une app accessoire au premier
        // plan de façon fiable — l'avertissement de compilation est attendu.
        NSApp.activate(ignoringOtherApps: true)
        fenetre?.makeKeyAndOrderFront(nil)
        fenetre?.makeFirstResponder(recherche)
    }

    private func construire() {
        let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        f.title = "Dictée — historique"
        f.center()
        f.isReleasedWhenClosed = false

        recherche.placeholderString = "rechercher…"
        recherche.delegate = self
        recherche.translatesAutoresizingMaskIntoConstraints = false

        let colonne = NSTableColumn(identifier: .init("dictee"))
        colonne.resizingMask = .autoresizingMask
        table.addTableColumn(colonne)
        table.headerView = nil
        table.rowHeight = 26
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicLigne)
        table.style = .inset

        table.surEntree = { [weak self] i in
            guard let self, i < affichees.count else { return }
            let texte = affichees[i].texte
            fenetre?.orderOut(nil)
            surRecoller?(texte, appPrecedente)
        }
        table.surSuppression = { [weak self] i in
            guard let self, i < affichees.count else { return }
            try? historique.supprimer(id: affichees[i].id)
            rafraichir()
        }
        table.surEchappement = { [weak self] in self?.fenetre?.orderOut(nil) }

        let defilement = NSScrollView()
        defilement.documentView = table
        defilement.hasVerticalScroller = true
        defilement.translatesAutoresizingMaskIntoConstraints = false

        let contenu = NSView()
        contenu.addSubview(recherche)
        contenu.addSubview(defilement)
        NSLayoutConstraint.activate([
            recherche.topAnchor.constraint(equalTo: contenu.topAnchor, constant: 10),
            recherche.leadingAnchor.constraint(equalTo: contenu.leadingAnchor, constant: 10),
            recherche.trailingAnchor.constraint(equalTo: contenu.trailingAnchor, constant: -10),
            defilement.topAnchor.constraint(equalTo: recherche.bottomAnchor, constant: 10),
            defilement.leadingAnchor.constraint(equalTo: contenu.leadingAnchor),
            defilement.trailingAnchor.constraint(equalTo: contenu.trailingAnchor),
            defilement.bottomAnchor.constraint(equalTo: contenu.bottomAnchor),
        ])
        f.contentView = contenu
        fenetre = f
    }

    private func rafraichir() {
        affichees = historique.rechercher(recherche.stringValue)
        table.reloadData()
    }

    // ── source de données ─────────────────────────────────────────────────

    public func numberOfRows(in tableView: NSTableView) -> Int { affichees.count }

    public func tableView(_ t: NSTableView, viewFor colonne: NSTableColumn?,
                          row: Int) -> NSView? {
        let d = affichees[row]
        let cellule = NSTableCellView()

        let heure = NSTextField(labelWithString: FenetreHistorique.horodatage(d.date))
        heure.textColor = .secondaryLabelColor
        heure.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        heure.translatesAutoresizingMaskIntoConstraints = false

        let texte = NSTextField(labelWithString: d.texte)
        texte.lineBreakMode = .byTruncatingTail
        texte.translatesAutoresizingMaskIntoConstraints = false

        cellule.addSubview(heure)
        cellule.addSubview(texte)
        NSLayoutConstraint.activate([
            heure.leadingAnchor.constraint(equalTo: cellule.leadingAnchor, constant: 8),
            heure.centerYAnchor.constraint(equalTo: cellule.centerYAnchor),
            heure.widthAnchor.constraint(equalToConstant: 92),
            texte.leadingAnchor.constraint(equalTo: heure.trailingAnchor, constant: 8),
            texte.trailingAnchor.constraint(equalTo: cellule.trailingAnchor, constant: -8),
            texte.centerYAnchor.constraint(equalTo: cellule.centerYAnchor),
        ])
        return cellule
    }

    /// Heure seule pour aujourd'hui, date courte au-delà.
    static func horodatage(_ d: Date, maintenant: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        if Calendar.current.isDate(d, inSameDayAs: maintenant) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "d MMM HH:mm"
        }
        return f.string(from: d)
    }

    // ── actions ───────────────────────────────────────────────────────────

    @objc private func clicLigne() {
        guard table.clickedRow >= 0, table.clickedRow < affichees.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(affichees[table.clickedRow].texte, forType: .string)
    }

    public func controlTextDidChange(_ obj: Notification) { rafraichir() }
}

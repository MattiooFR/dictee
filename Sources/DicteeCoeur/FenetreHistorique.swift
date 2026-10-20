import AppKit
import AVFoundation

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

/// Bouton de ligne : retient la dictée qu'il concerne, la ligne pouvant être
/// recyclée ou décalée par la recherche.
final class BoutonLigne: NSButton {
    var idDictee = ""
}

/// Fenêtre de consultation des dictées. Ne colle rien elle-même : elle délègue
/// via `surRecoller`, pour rester ignorante du mécanisme de collage.
public final class FenetreHistorique: NSObject, NSTableViewDataSource,
                                      NSTableViewDelegate, NSSearchFieldDelegate,
                                      AVAudioPlayerDelegate {
    private let historique: Historique
    private let archive: ArchiveAudio
    private var lecture: AVAudioPlayer?
    private var idEnLecture: String?
    private var fenetre: NSWindow?
    private var table = TableHistorique()
    private var recherche = NSSearchField()
    private var affichees: [Dictee] = []
    /// Application au premier plan au moment de l'ouverture : c'est là que le
    /// texte devra retourner.
    private var appPrecedente: NSRunningApplication?

    public var surRecoller: ((String, NSRunningApplication?) -> Void)?

    public init(historique: Historique, archive: ArchiveAudio) {
        self.historique = historique
        self.archive = archive
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
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: f,
                                               queue: .main) { [weak self] _ in self?.arreterLecture() }

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
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        table.surEntree = { [weak self] i in
            guard let self, i < affichees.count else { return }
            let texte = affichees[i].texte
            fenetre?.orderOut(nil)
            surRecoller?(texte, appPrecedente)
        }
        table.surSuppression = { [weak self] i in
            guard let self, i < affichees.count else { return }
            let id = affichees[i].id
            if idEnLecture == id { arreterLecture() }
            try? historique.supprimer(id: id)
            try? archive.supprimer(id)
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
            texte.centerYAnchor.constraint(equalTo: cellule.centerYAnchor),
        ])

        guard archive.fichier(d.id) != nil else {
            texte.trailingAnchor.constraint(equalTo: cellule.trailingAnchor, constant: -8).isActive = true
            return cellule
        }
        let ecouter = bouton(idEnLecture == d.id ? "stop.fill" : "play.fill",
                             idEnLecture == d.id ? "Arrêter" : "Écouter l’audio", d.id, #selector(basculerLecture(_:)))
        let copier = bouton("waveform", "Copier l’audio (⌘V pour l’envoyer, ou glisser la ligne)",
                            d.id, #selector(copierAudio(_:)))
        let boutons = NSStackView(views: [ecouter, copier])
        boutons.spacing = 2
        boutons.translatesAutoresizingMaskIntoConstraints = false
        cellule.addSubview(boutons)
        NSLayoutConstraint.activate([
            boutons.trailingAnchor.constraint(equalTo: cellule.trailingAnchor, constant: -6),
            boutons.centerYAnchor.constraint(equalTo: cellule.centerYAnchor),
            texte.trailingAnchor.constraint(equalTo: boutons.leadingAnchor, constant: -8),
        ])
        return cellule
    }

    private func bouton(_ symbole: String, _ aide: String, _ id: String, _ action: Selector) -> BoutonLigne {
        let b = BoutonLigne()
        b.image = NSImage(systemSymbolName: symbole, accessibilityDescription: aide)
        b.bezelStyle = .accessoryBarAction
        b.isBordered = false
        b.toolTip = aide
        b.idDictee = id
        b.target = self
        b.action = action
        return b
    }

    /// Glisser une ligne qui a un audio dépose ce fichier (WhatsApp, Mail, Finder…).
    public func tableView(_ t: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < affichees.count, let u = copieAEnvoyer(affichees[row]) else { return nil }
        return u as NSURL
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

    @objc private func copierAudio(_ b: BoutonLigne) {
        guard let d = affichees.first(where: { $0.id == b.idDictee }), let u = copieAEnvoyer(d) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([u as NSURL])
        b.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Audio copié")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            b.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Copier l’audio")
        }
    }

    /// Copie temporaire au nom lisible : le destinataire voit « Dictée 20 oct 20h17.wav »,
    /// pas l'identifiant interne. L'archive, elle, reste privée.
    private func copieAEnvoyer(_ d: Dictee) -> URL? {
        guard let source = archive.fichier(d.id) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM HH'h'mm"
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-envoi-\(d.id)")
        let cible = dossier.appendingPathComponent("Dictée \(f.string(from: d.date)).wav")
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: cible.path) { try FileManager.default.removeItem(at: cible) }
            try FileManager.default.copyItem(at: source, to: cible)
            return cible
        } catch {
            journaliser("copie audio impossible : \(error)")
            return nil
        }
    }

    @objc private func basculerLecture(_ b: BoutonLigne) {
        if idEnLecture == b.idDictee { arreterLecture(); return }
        arreterLecture()
        guard let u = archive.fichier(b.idDictee), let p = try? AVAudioPlayer(contentsOf: u) else { return }
        p.delegate = self
        p.play()
        lecture = p
        idEnLecture = b.idDictee
        table.reloadData()
    }

    private func arreterLecture() {
        lecture?.stop()
        lecture = nil
        guard idEnLecture != nil else { return }
        idEnLecture = nil
        table.reloadData()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, lecture === player else { return }
            arreterLecture()
        }
    }

    public func controlTextDidChange(_ obj: Notification) { rafraichir() }
}

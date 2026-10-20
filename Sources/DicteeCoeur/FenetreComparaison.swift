import AppKit

public final class FenetreComparaison {
    private var fenetre: NSWindow?
    private var statut: NSTextField?
    private var textes: [ModeleLocal: NSTextView] = [:]
    private var mesures: [ModeleLocal: NSTextField] = [:]
    public private(set) var disponible = false

    public func ouvrir() {
        if fenetre == nil { construire() }
        NSApp.activate(ignoringOtherApps: true)
        fenetre?.makeKeyAndOrderFront(nil)
    }

    public func commencer() {
        ouvrir()
        disponible = true
        statut?.stringValue = "Comparaison en cours…"
        for modele in ModeleLocal.allCases {
            textes[modele]?.string = "En attente…"
            mesures[modele]?.stringValue = ""
        }
    }

    public func progression(_ modele: ModeleLocal) {
        statut?.stringValue = "Chargement et transcription : \(modele.titre)…"
    }

    public func afficher(_ resultats: [ResultatComparaison]) {
        let erreurs = resultats.filter { $0.erreur != nil }.count
        statut?.stringValue = erreurs == 0 ? "Comparaison terminée — sélectionne un texte pour le copier."
            : "Comparaison terminée — \(erreurs) modèle(s) en erreur."
        for resultat in resultats {
            textes[resultat.modele]?.string = resultat.erreur ?? (resultat.texte.isEmpty ? "Aucune parole reconnue." : resultat.texte)
            if let r = resultat.reponse {
                var valeurs = [String(format: "Transcription : %.0f ms", r.secondes * 1000)]
                if let d = r.demarrageSecondes { valeurs.append(String(format: "Démarrage : %.2f s", d)) }
                if let m = r.memoireMio { valeurs.append(String(format: "Pic MLX : %.2f Go", m * 1048576 / 1e9)) }
                mesures[resultat.modele]?.stringValue = valeurs.joined(separator: "  ·  ")
            }
        }
        ouvrir()
    }

    private func construire() {
        let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 660),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        f.title = "Dictée — comparaison des modèles"
        f.isReleasedWhenClosed = false
        f.minSize = NSSize(width: 650, height: 520)
        f.center()
        let pile = NSStackView()
        pile.orientation = .vertical; pile.alignment = .leading; pile.spacing = 10
        pile.distribution = .fill
        pile.translatesAutoresizingMaskIntoConstraints = false
        let titre = NSTextField(labelWithString: "Un enregistrement, trois transcriptions")
        titre.font = .boldSystemFont(ofSize: 18)
        pile.addArrangedSubview(titre)
        let statut = NSTextField(wrappingLabelWithString: "Prêt à comparer")
        self.statut = statut; pile.addArrangedSubview(statut)
        var premierDefilement: NSScrollView?
        for modele in ModeleLocal.allCases {
            let nom = NSTextField(labelWithString: modele.titre)
            nom.font = .boldSystemFont(ofSize: 14); pile.addArrangedSubview(nom)
            let mesure = NSTextField(labelWithString: "")
            mesure.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            mesure.textColor = .secondaryLabelColor
            mesures[modele] = mesure; pile.addArrangedSubview(mesure)
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            let texte = NSTextView(frame: NSRect(x: 0, y: 0, width: 730, height: 90))
            texte.isEditable = false; texte.isSelectable = true; texte.isRichText = false
            texte.font = .systemFont(ofSize: 14)
            texte.textContainerInset = NSSize(width: 8, height: 8)
            texte.isHorizontallyResizable = false; texte.isVerticallyResizable = true
            texte.autoresizingMask = [.width]; texte.textContainer?.widthTracksTextView = true
            scroll.documentView = texte
            textes[modele] = texte; pile.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: pile.widthAnchor).isActive = true
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            if let premier = premierDefilement {
                scroll.heightAnchor.constraint(equalTo: premier.heightAnchor).isActive = true
            } else { premierDefilement = scroll }
        }
        let note = NSTextField(wrappingLabelWithString: "Même audio pour les trois modèles. Le temps de transcription exclut le démarrage. La mémoire MLX n’inclut pas toute la RAM de l’application.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        pile.addArrangedSubview(note)
        let contenu = NSView(); contenu.addSubview(pile); f.contentView = contenu
        NSLayoutConstraint.activate([
            pile.topAnchor.constraint(equalTo: contenu.topAnchor, constant: 20),
            pile.bottomAnchor.constraint(equalTo: contenu.bottomAnchor, constant: -20),
            pile.leadingAnchor.constraint(equalTo: contenu.leadingAnchor, constant: 20),
            pile.trailingAnchor.constraint(equalTo: contenu.trailingAnchor, constant: -20),
            statut.widthAnchor.constraint(equalTo: pile.widthAnchor),
            note.widthAnchor.constraint(equalTo: pile.widthAnchor),
        ])
        fenetre = f
    }
}

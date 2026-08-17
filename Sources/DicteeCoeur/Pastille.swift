import AppKit
import QuartzCore

/// Panneau flottant collé au bord droit.
///
/// C'est un `NSPanel` non activant : il reçoit les clics **sans** devenir la
/// fenêtre clé ni activer notre application. C'est ce qui laisse le focus à
/// l'application où l'utilisateur écrivait, donc ce qui permet au ⌘V du
/// collage d'atterrir au bon endroit.
public final class Pastille {
    public enum Apparence: Equatable {
        case repos, survol, actif

        /// Taille de la fenêtre. Elle épouse la forme pour ne pas avaler les
        /// clics destinés à ce qu'il y a dessous — au bord droit de l'écran
        /// vivent les barres de défilement.
        var fenetre: NSSize {
            switch self {
            case .repos:  return NSSize(width: 14, height: 56)
            case .survol: return NSSize(width: 20, height: 64)
            case .actif:  return NSSize(width: 32, height: 112)
            }
        }
        /// Taille de la forme dessinée, collée au bord droit de la fenêtre.
        var forme: CGSize {
            switch self {
            case .repos:  return CGSize(width: 6, height: 48)
            case .survol: return CGSize(width: 8, height: 52)
            case .actif:  return CGSize(width: 24, height: 104)
            }
        }
        var rayon: CGFloat {
            switch self {
            case .repos:  return 3
            case .survol: return 4
            case .actif:  return 12
            }
        }
    }

    private let fenetre: NSPanel
    private let vue: VuePastille
    private var apparenceCourante: Apparence = .repos
    private var etatCourant: EtatPastille = .repos

    public var surClic: (() -> Void)? {
        get { vue.surClic }
        set { vue.surClic = newValue }
    }

    public init() {
        let taille = Apparence.repos.fenetre
        fenetre = NSPanel(contentRect: NSRect(origin: .zero, size: taille),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        fenetre.isOpaque = false
        fenetre.backgroundColor = .clear
        fenetre.hasShadow = false
        fenetre.level = .screenSaver
        fenetre.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        fenetre.becomesKeyOnlyIfNeeded = true
        fenetre.isFloatingPanel = true
        fenetre.ignoresMouseEvents = false

        vue = VuePastille(frame: NSRect(origin: .zero, size: taille))
        fenetre.contentView = vue
        repositionner()
        fenetre.orderFrontRegardless()

        vue.surApparence = { [weak self] a in self?.appliquer(a) }
        vue.surEntree = { [weak self] in
            guard let self, auRepos else { return }
            appliquer(.survol)
            vue.eclaircir(true)
        }
        vue.surSortie = { [weak self] in
            guard let self, auRepos else { return }
            appliquer(.repos)
            vue.eclaircir(false)
        }
        vue.afficher(.repos)
    }

    private var auRepos: Bool { etatCourant == .repos }

    /// À rappeler au début de chaque dictée : l'écran actif peut avoir changé.
    public func repositionner() {
        placer(apparenceCourante)
    }

    /// Redimensionne la fenêtre PUIS anime la forme. Jamais l'inverse, et
    /// jamais pendant une animation en cours : `setFrame` sous animation
    /// produit des sautillements.
    func appliquer(_ a: Apparence) {
        guard a != apparenceCourante else { return }
        apparenceCourante = a
        placer(a)
        vue.reancrer()
        vue.versForme(a)
    }

    private func placer(_ a: Apparence) {
        guard let ecran = NSScreen.main else { return }
        let c = ecran.frame
        let t = a.fenetre
        fenetre.setFrame(NSRect(x: c.maxX - t.width, y: c.midY - t.height / 2,
                                width: t.width, height: t.height),
                         display: true, animate: false)
    }

    public func afficher(_ etat: EtatPastille, persistant: Bool = false) {
        etatCourant = etat
        vue.afficher(etat, persistant: persistant)
    }

    /// Convertit un niveau dBFS en [0,1] et le transmet au ressort.
    public func niveau(_ dbfs: Float) {
        vue.niveau(CGFloat(max(0, min(1, (dbfs + 50) / 50))))
    }
}

final class VuePastille: NSView {
    // ── géométrie des barres ──────────────────────────────────────────────
    private static let nombreBarres = 9
    private static let hauteurBarre: CGFloat = 3
    private static let largeurMin: CGFloat = 4
    private static let largeurMax: CGFloat = 14
    /// Décalage, en images, entre deux barres voisines. C'est lui qui fait
    /// monter la vague le long du bandeau au lieu de tout faire pulser d'un bloc.
    private static let decalageImages = 4
    /// Distance entre l'axe des barres et le bord droit de la fenêtre.
    private static let axeDepuisBord: CGFloat = 12

    private let forme = CALayer()
    private let glyphe = CALayer()
    private var barres: [CALayer] = []

    // ── ressort amorti ────────────────────────────────────────────────────
    private var cible: CGFloat = 0
    private var courant: CGFloat = 0
    private var vitesse: CGFloat = 0
    private var lien: CADisplayLink?
    private static let raideur: CGFloat = 180
    private static let amortissement: CGFloat = 22

    /// Historique circulaire du niveau lissé : chaque barre y lit une valeur
    /// plus ancienne que sa voisine du dessous.
    private var historique = [CGFloat](repeating: 0, count: 64)
    private var curseur = 0

    private enum ModeAnimation { case voix, attente }
    private var mode: ModeAnimation = .voix
    private var phaseAttente: CGFloat = 0

    /// Incrémentée à chaque changement d'état. Un retour différé (succès →
    /// repos, erreur → repos) ne s'applique que si aucun état plus récent
    /// n'est arrivé entre-temps.
    private var generation = 0

    /// La vue ne connaît pas sa fenêtre : elle demande le redimensionnement.
    var surApparence: ((Pastille.Apparence) -> Void)?
    var surEntree: (() -> Void)?
    var surSortie: (() -> Void)?
    var surClic: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Ordre imposé par AppKit pour une vue hôte de calque : `layer` d'abord,
        // `wantsLayer` ensuite. L'inverse fait remplacer le calque par le système.
        let racine = CALayer()
        racine.frame = bounds
        layer = racine
        wantsLayer = true

        // Ancrage à droite : quand la fenêtre grandit vers la gauche, la forme
        // reste collée au bord et s'étire dans le bon sens — l'effet tiroir.
        forme.anchorPoint = CGPoint(x: 1, y: 0.5)
        forme.bounds = CGRect(origin: .zero, size: Pastille.Apparence.repos.forme)
        forme.cornerRadius = Pastille.Apparence.repos.rayon
        forme.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        forme.backgroundColor = NSColor(white: 0.35, alpha: 0.55).cgColor
        racine.addSublayer(forme)

        for _ in 0..<Self.nombreBarres {
            let b = CALayer()
            b.backgroundColor = NSColor(white: 1, alpha: 0.9).cgColor
            b.cornerRadius = Self.hauteurBarre / 2
            b.bounds = CGRect(x: 0, y: 0, width: Self.largeurMin, height: Self.hauteurBarre)
            b.opacity = 0
            racine.addSublayer(b)
            barres.append(b)
        }

        // Dimensions en init, position dans `reancrer()` : régler `frame` ferait
        // les deux à la fois et écraserait le repositionnement.
        glyphe.bounds = CGRect(origin: .zero, size: CGSize(width: 16, height: 16))
        glyphe.contents = VuePastille.symbole("checkmark", taille: 13)
        glyphe.opacity = 0
        racine.addSublayer(glyphe)

        reancrer()
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    // ── survol et clic ────────────────────────────────────────────────────

    /// `.activeAlways` est indispensable : les options par défaut ne délivrent
    /// d'événements que si la fenêtre est clé, ce qu'un panneau non activant
    /// n'est jamais.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for z in trackingAreas { removeTrackingArea(z) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways,
                                                 .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { surEntree?() }
    override func mouseExited(with event: NSEvent) { surSortie?() }
    override func mouseDown(with event: NSEvent) { surClic?() }

    // ── placement ─────────────────────────────────────────────────────────

    /// Après un changement de taille de fenêtre : replace les calques dans les
    /// nouvelles coordonnées, sans animation.
    func reancrer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        forme.position = CGPoint(x: bounds.maxX, y: bounds.midY)
        glyphe.position = CGPoint(x: bounds.maxX - Self.axeDepuisBord, y: bounds.midY)
        placerBarres()
        CATransaction.commit()
    }

    func versForme(_ a: Pastille.Apparence) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        forme.bounds = CGRect(origin: .zero, size: a.forme)
        forme.cornerRadius = a.rayon
        CATransaction.commit()
    }

    private func placerBarres() {
        let centreX = bounds.maxX - Self.axeDepuisBord
        let hauteur = Pastille.Apparence.actif.forme.height
        let depart = bounds.midY - hauteur / 2 + 12
        let pas = (hauteur - 24) / CGFloat(Self.nombreBarres - 1)
        for (k, b) in barres.enumerated() {
            b.position = CGPoint(x: centreX, y: depart + CGFloat(k) * pas)
        }
    }

    // ── états ─────────────────────────────────────────────────────────────

    /// `persistant` : l'état rouge ne revient pas au repos tout seul.
    /// Réservé aux autorisations manquantes, que seul l'utilisateur peut lever.
    func afficher(_ etat: EtatPastille, persistant: Bool = false) {
        generation += 1
        let g = generation

        switch etat {
        case .repos:
            arreterAnimation()
            surApparence?(.repos)
            couleur(NSColor(white: 0.35, alpha: 0.55))
            glyphe.opacity = 0

        case .ecoute:
            surApparence?(.actif)
            couleur(NSColor(white: 0.08, alpha: 0.92))
            glyphe.opacity = 0
            demarrerAnimation(.voix)

        case .transcription:
            surApparence?(.actif)
            couleur(NSColor(white: 0.08, alpha: 0.92))
            glyphe.opacity = 0
            // Les mêmes barres, nourries par une onde lente : ça reste du
            // mouvement de la même famille, sans introduire un second langage.
            demarrerAnimation(.attente)

        case .succes:
            arreterAnimation()
            surApparence?(.actif)
            couleur(NSColor(white: 0.08, alpha: 0.92))
            glyphe.contents = VuePastille.symbole("checkmark", taille: 13,
                                                  couleur: .systemGreen)
            glyphe.opacity = 1
            apres(0.35) { if g == self.generation { self.afficher(.repos) } }

        case .annule:
            // Referme aussi le bandeau : on peut arriver ici depuis
            // `.transcription` (dictée silencieuse), pas seulement depuis un
            // appui bref où rien ne s'était ouvert.
            arreterAnimation()
            surApparence?(.repos)
            couleur(NSColor(white: 0.35, alpha: 0.55))
            glyphe.opacity = 0
            pulser()

        case .erreur:
            arreterAnimation()
            surApparence?(.actif)
            couleur(NSColor.systemRed.withAlphaComponent(0.92))
            glyphe.contents = VuePastille.symbole("exclamationmark", taille: 13)
            glyphe.opacity = 1
            if persistant { break }   // autorisation manquante : on reste rouge
            apres(2.5) { if g == self.generation { self.afficher(.repos) } }
        }
    }

    func eclaircir(_ actif: Bool) {
        couleur(actif ? NSColor(white: 0.75, alpha: 0.85)
                      : NSColor(white: 0.35, alpha: 0.55), duree: 0.15)
    }

    // ── niveau de voix ────────────────────────────────────────────────────

    /// Niveau visé, dans [0,1]. Appelé ~46 fois par seconde pendant la capture.
    func niveau(_ n: CGFloat) { cible = max(0, min(1, n)) }

    private func demarrerAnimation(_ m: ModeAnimation) {
        mode = m
        if m == .attente { cible = 0 }
        montrerBarres(true)
        guard lien == nil else { return }
        let l = displayLink(target: self, selector: #selector(pas(_:)))
        l.add(to: .main, forMode: .common)
        lien = l
    }

    private func arreterAnimation() {
        lien?.invalidate(); lien = nil
        cible = 0; courant = 0; vitesse = 0; phaseAttente = 0
        historique = [CGFloat](repeating: 0, count: historique.count)
        montrerBarres(false)
    }

    private func montrerBarres(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        for b in barres { b.opacity = visible ? 1 : 0 }
        CATransaction.commit()
    }

    @objc private func pas(_ lien: CADisplayLink) {
        let dt = CGFloat(min(lien.duration, 1.0 / 30))

        switch mode {
        case .voix:
            let acceleration = Self.raideur * (cible - courant) - Self.amortissement * vitesse
            vitesse += acceleration * dt
            courant += vitesse * dt
        case .attente:
            phaseAttente += dt * 3.2
            courant = 0.18 + 0.14 * (sin(phaseAttente) + 1) / 2
        }

        curseur = (curseur + 1) % historique.count
        historique[curseur] = max(0, min(1, courant))
        appliquerBarres()
    }

    private func appliquerBarres() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // sinon Core Animation anime chaque pas
        for (k, b) in barres.enumerated() {
            let recul = k * Self.decalageImages
            let i = (curseur - recul + historique.count * 2) % historique.count
            let n = historique[i]
            let largeur = Self.largeurMin + (Self.largeurMax - Self.largeurMin) * n
            b.bounds = CGRect(x: 0, y: 0, width: largeur, height: Self.hauteurBarre)
            b.opacity = Float(0.45 + 0.55 * n)
        }
        CATransaction.commit()
    }

    // ── primitives d'animation ────────────────────────────────────────────

    private func couleur(_ c: NSColor, duree: CFTimeInterval = 0.18) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duree)
        forme.backgroundColor = c.cgColor
        CATransaction.commit()
    }

    private func pulser() {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0.55, 1.0, 0.55]
        a.keyTimes = [0, 0.4, 1]
        a.duration = 0.45
        forme.add(a, forKey: "pulsation")
    }

    private func apres(_ delai: TimeInterval, _ bloc: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delai, execute: bloc)
    }

    /// Rend un symbole SF teinté, prêt à servir de `contents` de calque.
    static func symbole(_ nom: String, taille: CGFloat,
                        couleur: NSColor = .white) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: taille, weight: .semibold)
        guard let brut = NSImage(systemSymbolName: nom, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let teinte = NSImage(size: brut.size, flipped: false) { rect in
            brut.draw(in: rect)
            couleur.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        var rect = NSRect(origin: .zero, size: teinte.size)
        return teinte.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

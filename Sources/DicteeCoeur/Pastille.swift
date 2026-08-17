import AppKit
import QuartzCore

/// Fenêtre flottante collée au bord droit. Elle ne peut ni prendre le focus ni
/// intercepter un clic : c'est ce qui garantit que le ⌘V du collage atterrit
/// dans l'application où l'utilisateur écrivait.
public final class Pastille {
    static let cote: CGFloat = 120                                        // fenêtre
    static let capsule = CGRect(x: 114, y: 36, width: 6, height: 48)      // au repos
    static let bandeau = CGRect(x: 96, y: 8, width: 24, height: 104)      // actif

    private let fenetre: NSWindow
    private let vue: VuePastille

    public init() {
        let taille = NSSize(width: Pastille.cote, height: Pastille.cote)
        fenetre = NSWindow(contentRect: NSRect(origin: .zero, size: taille),
                           styleMask: .borderless, backing: .buffered, defer: false)
        fenetre.isOpaque = false
        fenetre.backgroundColor = .clear
        fenetre.hasShadow = false
        fenetre.level = .screenSaver
        fenetre.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        fenetre.ignoresMouseEvents = true

        vue = VuePastille(frame: NSRect(origin: .zero, size: taille))
        fenetre.contentView = vue
        repositionner()
        fenetre.orderFrontRegardless()
        vue.afficher(.repos)
    }

    /// À rappeler au début de chaque dictée : l'écran actif peut avoir changé.
    public func repositionner() {
        guard let ecran = NSScreen.main else { return }
        let c = ecran.frame
        fenetre.setFrameOrigin(NSPoint(x: c.maxX - Pastille.cote,
                                       y: c.midY - Pastille.cote / 2))
    }

    public func afficher(_ etat: EtatPastille, persistant: Bool = false) {
        vue.afficher(etat, persistant: persistant)
    }

    /// Convertit un niveau dBFS en [0,1] et le transmet au ressort.
    public func niveau(_ dbfs: Float) {
        vue.viser(CGFloat(max(0, min(1, (dbfs + 50) / 50))))
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Ordre imposé par AppKit pour une vue hôte de calque : `layer` d'abord,
        // `wantsLayer` ensuite. L'inverse fait remplacer le calque par le système.
        let racine = CALayer()
        racine.frame = bounds
        layer = racine
        wantsLayer = true

        forme.frame = Pastille.capsule
        forme.cornerRadius = 3
        forme.backgroundColor = NSColor(white: 0.35, alpha: 0.55).cgColor
        // Le bandeau est au ras du bord droit : seuls les coins gauches sont
        // arrondis, comme un tiroir qui sort de la tranche de l'écran.
        forme.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        racine.addSublayer(forme)

        let centreX = Pastille.bandeau.midX
        let hautDépart = Pastille.bandeau.minY + 12
        let pas = (Pastille.bandeau.height - 24) / CGFloat(Self.nombreBarres - 1)
        for k in 0..<Self.nombreBarres {
            let b = CALayer()
            b.backgroundColor = NSColor(white: 1, alpha: 0.9).cgColor
            b.cornerRadius = Self.hauteurBarre / 2
            b.bounds = CGRect(x: 0, y: 0, width: Self.largeurMin, height: Self.hauteurBarre)
            b.position = CGPoint(x: centreX, y: hautDépart + CGFloat(k) * pas)
            b.opacity = 0
            racine.addSublayer(b)
            barres.append(b)
        }

        glyphe.frame = CGRect(x: centreX - 8, y: Pastille.bandeau.midY - 8,
                              width: 16, height: 16)
        glyphe.contents = VuePastille.symbole("checkmark", taille: 13)
        glyphe.opacity = 0
        racine.addSublayer(glyphe)
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    /// `persistant` : l'état rouge ne revient pas au repos tout seul.
    /// Réservé aux autorisations manquantes, que seul l'utilisateur peut lever.
    func afficher(_ etat: EtatPastille, persistant: Bool = false) {
        generation += 1
        let g = generation

        switch etat {
        case .repos:
            arreterAnimation()
            versCapsule(couleur: NSColor(white: 0.35, alpha: 0.55))
            glyphe.opacity = 0

        case .ecoute:
            versBandeau(couleur: NSColor(white: 0.08, alpha: 0.92))
            glyphe.opacity = 0
            demarrerAnimation(.voix)

        case .transcription:
            versBandeau(couleur: NSColor(white: 0.08, alpha: 0.92))
            glyphe.opacity = 0
            // Les mêmes barres, nourries par une onde lente : ça reste du
            // mouvement de la même famille, sans introduire un second langage.
            demarrerAnimation(.attente)

        case .succes:
            arreterAnimation()
            versBandeau(couleur: NSColor(white: 0.08, alpha: 0.92))
            glyphe.contents = VuePastille.symbole("checkmark", taille: 13,
                                                  couleur: .systemGreen)
            glyphe.opacity = 1
            apres(0.35) { if g == self.generation { self.afficher(.repos) } }

        case .annule:
            // Referme aussi le bandeau : on peut arriver ici depuis
            // `.transcription` (dictée silencieuse), pas seulement depuis un
            // appui bref où rien ne s'était ouvert.
            arreterAnimation()
            versCapsule(couleur: NSColor(white: 0.35, alpha: 0.55))
            glyphe.opacity = 0
            pulser()

        case .erreur:
            arreterAnimation()
            versBandeau(couleur: NSColor.systemRed.withAlphaComponent(0.92))
            glyphe.contents = VuePastille.symbole("exclamationmark", taille: 13)
            glyphe.opacity = 1
            if persistant { break }   // autorisation manquante : on reste rouge
            apres(2.5) { if g == self.generation { self.afficher(.repos) } }
        }
    }

    // ── niveau de voix ────────────────────────────────────────────────────

    /// Niveau visé, dans [0,1]. Appelé ~46 fois par seconde pendant la capture.
    func viser(_ n: CGFloat) { cible = max(0, min(1, n)) }

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

    // ── formes et animations ──────────────────────────────────────────────

    private func versCapsule(couleur: NSColor) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        forme.frame = Pastille.capsule
        forme.cornerRadius = 3
        forme.backgroundColor = couleur.cgColor
        CATransaction.commit()
    }

    private func versBandeau(couleur: NSColor) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        forme.frame = Pastille.bandeau
        forme.cornerRadius = 12
        forme.backgroundColor = couleur.cgColor
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

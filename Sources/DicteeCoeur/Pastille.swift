import AppKit
import QuartzCore

/// Fenêtre flottante collée au bord droit. Elle ne peut ni prendre le focus ni
/// intercepter un clic : c'est ce qui garantit que le ⌘V du collage atterrit
/// dans l'application où l'utilisateur écrivait.
public final class Pastille {
    static let cote: CGFloat = 120          // côté de la fenêtre
    static let capsule = CGRect(x: 114, y: 36, width: 6, height: 48)
    static let cercle  = CGRect(x: 52, y: 32, width: 56, height: 56)

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

    public func afficher(_ etat: EtatPastille) { vue.afficher(etat) }

    /// Convertit un niveau dBFS en [0,1] et le transmet au ressort.
    public func niveau(_ dbfs: Float) {
        vue.viser(CGFloat(max(0, min(1, (dbfs + 50) / 50))))
    }
}

final class VuePastille: NSView {
    private let anneau = CAShapeLayer()
    private let forme = CALayer()
    private let glyphe = CALayer()
    private let arc = CAShapeLayer()

    // Ressort amorti : position/vitesse intégrées à chaque rafraîchissement.
    private var cible: CGFloat = 0
    private var courant: CGFloat = 0
    private var vitesse: CGFloat = 0
    private var lien: CADisplayLink?
    private static let raideur: CGFloat = 180
    private static let amortissement: CGFloat = 22

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Ordre imposé par AppKit pour une vue hôte de calque : `layer` d'abord,
        // `wantsLayer` ensuite. L'inverse fait remplacer le calque par le système.
        let racine = CALayer()
        racine.frame = bounds
        layer = racine
        wantsLayer = true

        anneau.frame = Pastille.cercle
        anneau.fillColor = nil
        anneau.lineWidth = 2
        anneau.strokeColor = NSColor(white: 1, alpha: 0.55).cgColor
        anneau.path = CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 52, height: 52),
                             transform: nil)
        anneau.opacity = 0
        racine.addSublayer(anneau)

        forme.frame = Pastille.capsule
        forme.cornerRadius = 3
        forme.backgroundColor = NSColor(white: 0.35, alpha: 0.55).cgColor
        racine.addSublayer(forme)

        arc.frame = Pastille.cercle
        arc.fillColor = nil
        arc.lineWidth = 3
        arc.lineCap = .round
        arc.strokeColor = NSColor.white.cgColor
        arc.opacity = 0
        arc.path = CGPath(ellipseIn: CGRect(x: 14, y: 14, width: 28, height: 28),
                          transform: nil)
        arc.strokeStart = 0
        arc.strokeEnd = 0.25
        racine.addSublayer(arc)

        glyphe.frame = CGRect(x: Pastille.cercle.midX - 11, y: Pastille.cercle.midY - 11,
                              width: 22, height: 22)
        glyphe.contents = VuePastille.symbole("mic.fill", taille: 18)
        glyphe.opacity = 0
        racine.addSublayer(glyphe)
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    func afficher(_ etat: EtatPastille) {
        switch etat {
        case .repos:
            arreterRessort()
            versCapsule(couleur: NSColor(white: 0.35, alpha: 0.55))
            cacherArcEtGlyphe()

        case .ecoute:
            versCercle(couleur: NSColor(white: 0.08, alpha: 0.92))
            arc.opacity = 0
            arreterRotation()
            glyphe.contents = VuePastille.symbole("mic.fill", taille: 18)
            glyphe.opacity = 1
            demarrerRessort()

        case .transcription:
            arreterRessort()
            versCercle(couleur: NSColor(white: 0.08, alpha: 0.92))
            glyphe.opacity = 0
            arc.opacity = 1
            demarrerRotation()

        case .succes:
            arreterRessort()
            arc.opacity = 0
            arreterRotation()
            glyphe.contents = VuePastille.symbole("checkmark", taille: 18, couleur: .systemGreen)
            glyphe.opacity = 1
            apres(0.25) { self.afficher(.repos) }

        case .annule:
            arreterRessort()
            pulser()

        case .erreur:
            arreterRessort()
            versCercle(couleur: NSColor.systemRed.withAlphaComponent(0.92))
            arc.opacity = 0
            arreterRotation()
            glyphe.contents = VuePastille.symbole("exclamationmark", taille: 18)
            glyphe.opacity = 1
            apres(2.5) { self.afficher(.repos) }
        }
    }

    // ── niveau de voix ────────────────────────────────────────────────────

    /// Niveau visé, dans [0,1]. Appelé ~46 fois par seconde pendant la capture.
    func viser(_ n: CGFloat) { cible = max(0, min(1, n)) }

    private func demarrerRessort() {
        guard lien == nil else { return }
        anneau.opacity = 1
        let l = displayLink(target: self, selector: #selector(pas(_:)))
        l.add(to: .main, forMode: .common)
        lien = l
    }

    private func arreterRessort() {
        lien?.invalidate(); lien = nil
        anneau.opacity = 0
        cible = 0; courant = 0; vitesse = 0
        appliquerAnneau()
    }

    @objc private func pas(_ lien: CADisplayLink) {
        let dt = CGFloat(min(lien.duration, 1.0 / 30))
        let acceleration = Self.raideur * (cible - courant) - Self.amortissement * vitesse
        vitesse += acceleration * dt
        courant += vitesse * dt
        appliquerAnneau()
    }

    private func appliquerAnneau() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // sinon Core Animation anime chaque pas
        let echelle = 1 + 0.45 * max(0, courant)
        anneau.transform = CATransform3DMakeScale(echelle, echelle, 1)
        anneau.opacity = Float(0.35 + 0.5 * max(0, min(1, courant)))
        CATransaction.commit()
    }

    // ── formes et animations ──────────────────────────────────────────────

    private func versCapsule(couleur: NSColor) {
        forme.frame = Pastille.capsule
        forme.cornerRadius = 3
        forme.backgroundColor = couleur.cgColor
    }

    private func versCercle(couleur: NSColor) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        forme.frame = Pastille.cercle
        forme.cornerRadius = Pastille.cercle.width / 2
        forme.backgroundColor = couleur.cgColor
        CATransaction.commit()
    }

    private func cacherArcEtGlyphe() { glyphe.opacity = 0; arc.opacity = 0; arreterRotation() }

    private func demarrerRotation() {
        guard arc.animation(forKey: "rotation") == nil else { return }
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = -Double.pi * 2
        a.duration = 0.9
        a.repeatCount = .infinity
        arc.add(a, forKey: "rotation")
    }

    private func arreterRotation() { arc.removeAnimation(forKey: "rotation") }

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
        let config = NSImage.SymbolConfiguration(pointSize: taille, weight: .medium)
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

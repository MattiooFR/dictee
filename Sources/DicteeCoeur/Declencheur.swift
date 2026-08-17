import AppKit
import CoreGraphics

public enum ErreurDeclencheur: Error, Equatable { case surveillanceRefusee }

/// Écoute ⌘ droite sans jamais consommer les événements.
public final class Declencheur {
    public enum Signal: Equatable { case appui, relachement, autreTouche }

    /// Bit positionné par le système quand ⌘ *droite* est physiquement enfoncée.
    private static let bitCommandeDroite: UInt64 = 0x0000_0010

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var enfoncee = false
    private let signaler: (Signal) -> Void

    public init(signaler: @escaping (Signal) -> Void) { self.signaler = signaler }

    /// Surveillance des entrées — nécessaire pour créer le tap.
    public static func autorisationAccordee() -> Bool { CGPreflightListenEventAccess() }
    public static func demanderAutorisation() { _ = CGRequestListenEventAccess() }

    /// Accessibilité — nécessaire pour poster le ⌘V du collage.
    public static func accessibiliteAccordee() -> Bool { AXIsProcessTrusted() }

    public func demarrer() throws {
        let masque = (1 << CGEventType.flagsChanged.rawValue)
                   | (1 << CGEventType.keyDown.rawValue)

        let rappel: CGEventTapCallBack = { _, type, event, contexte in
            guard let contexte else { return Unmanaged.passUnretained(event) }
            let moi = Unmanaged<Declencheur>.fromOpaque(contexte).takeUnretainedValue()
            moi.traiter(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(masque),
                                          callback: rappel,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { throw ErreurDeclencheur.surveillanceRefusee }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func traiter(type: CGEventType, event: CGEvent) {
        // macOS désactive un tap qui répond trop lentement. Sans ce réarmement,
        // l'outil meurt silencieusement au bout de quelques jours.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        switch type {
        case .flagsChanged:
            let maintenant = (event.flags.rawValue & Self.bitCommandeDroite) != 0
            guard maintenant != enfoncee else { return }
            enfoncee = maintenant
            let s: Signal = maintenant ? .appui : .relachement
            DispatchQueue.main.async { self.signaler(s) }

        case .keyDown:
            guard enfoncee else { return }
            DispatchQueue.main.async { self.signaler(.autreTouche) }

        default:
            break
        }
    }

    public func arreter() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; enfoncee = false
    }
}

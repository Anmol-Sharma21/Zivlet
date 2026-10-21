import AppKit

/// The floating panel every HUD uses (P1-40): borderless, non-activating, on every Space. A borderless window
/// cannot become key by default; this one can, so a click into a card's selectable details makes it key, and then
/// Escape closes the card. `becomesKeyOnlyIfNeeded` keeps a plain button click from taking the keyboard away from
/// the person's own app, so Escape works only once the card is key (D-M4-16).
public final class HUDWindow: NSPanel {
    override public var canBecomeKey: Bool { true }

    public init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }
}

import AppKit

/// The Drop Box's window (P2-55 §9.1, 19c D-BL1): borderless and non-activating, floating above normal windows on
/// every Space and in full screen, with the system shadow as its only depth cue. Always dark, like the island. It is
/// shown with `orderFrontRegardless`, so the frontmost app keeps the keyboard (prototype: showing kept the frontmost
/// app); a click into it makes it key without activating the app. It moves by its background; when the button comes
/// up after a move the controller decides, through the dock rules, where it lands. Escape, keys and key changes go
/// to closures.
public final class BoxPanel: NSPanel {
    public var onEscape: () -> Void = {}
    /// True when the panel became key, false when it resigned.
    public var onKeyChange: (Bool) -> Void = { _ in }
    /// The controller's key map; false lets AppKit handle the key.
    public var onKey: (NSEvent) -> Bool = { _ in false }
    /// The frame after a move by the background, when the button comes up.
    public var onMoveEnded: (NSRect) -> Void = { _ in }

    private var pressOrigin: NSPoint?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    /// On screen without taking the keyboard or activating Zivlet.
    public func show() { orderFrontRegardless() }

    override public func cancelOperation(_ sender: Any?) { onEscape() }

    override public func keyDown(with event: NSEvent) {
        if !onKey(event) { super.keyDown(with: event) }
    }

    override public func becomeKey() {
        super.becomeKey()
        onKeyChange(true)
    }

    override public func resignKey() {
        super.resignKey()
        onKeyChange(false)
    }

    override public func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: pressBegan()
        case .leftMouseUp: pressEnded()
        default: break
        }
        super.sendEvent(event)
    }

    func pressBegan() { pressOrigin = frame.origin }

    func pressEnded() {
        defer { pressOrigin = nil }
        guard let pressOrigin, pressOrigin != frame.origin else { return }
        onMoveEnded(frame)
    }
}

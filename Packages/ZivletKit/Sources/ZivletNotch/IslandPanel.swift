import AppKit

/// The island's window (D-N2): borderless and non-activating, above the menu bar (`.statusBar`) but below the wheel
/// and open menus, on every Space and in full screen, out of Mission Control's sweep and the window cycle. It becomes
/// key only after a click into a non-button area or the menu command, never main; key changes and Escape go to the
/// host instead of closing anything here.
public final class IslandPanel: NSPanel {
    var onEscape: () -> Void = {}
    var onBecomeKey: () -> Void = {}
    var onResignKey: () -> Void = {}

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    override public func cancelOperation(_ sender: Any?) { onEscape() }

    override public func becomeKey() {
        super.becomeKey()
        onBecomeKey()
    }

    override public func resignKey() {
        super.resignKey()
        onResignKey()
    }
}

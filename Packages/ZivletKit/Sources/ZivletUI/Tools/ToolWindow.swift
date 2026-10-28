import AppKit
import SwiftUI
import ZivletNotchCore

/// The tool window (P2-30, PRD FR-63, plan 20b A2, D-M7-10): a borderless, non-activating panel that becomes key
/// without activating Zivlet, so the person's own app stays frontmost while the window takes the keyboard. It floats
/// above normal windows and joins the active Space and full screen. It opens centred on the wheel and clamped to the
/// screen (`ToolWindowPlacement`), sized to its content at a fixed width. Escape runs Cancel and closes; Return runs
/// Apply when Apply is on and the tool is not working (the owner of the window decides when it closes after Apply).
/// The finish follows Reduce Transparency and Increase Contrast at once, like Show All.
public final class ToolWindow: NSPanel {
    public var onApply: () -> Void = {}
    public var onCancel: () -> Void = {}
    let state = ToolWindowState()
    private let hosting: NSHostingView<ToolWindowView>
    private var displayOptions: (any NSObjectProtocol)?

    public init() {
        hosting = NSHostingView(rootView: ToolWindowView(state: state))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: ToolWindowView.width, height: 1),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        contentView = hosting
        state.apply = { [weak self] in self?.applyIfAllowed() }
        state.cancel = { [weak self] in self?.cancelOperation(nil) }
        watchDisplayOptions()
    }

    isolated deinit {
        if let displayOptions { NSWorkspace.shared.notificationCenter.removeObserver(displayOptions) }
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    /// The model the window shows now; nil while it is closed.
    public var model: ToolWindowModel? { state.model }

    /// Puts `model` and the tool's `content` in the window without showing it.
    public func load(_ model: ToolWindowModel, content: AnyView) {
        state.content = content
        update(model)
        setAccessibilityLabel(model.title)
    }

    /// A new state for the open window (Apply's state, busy); the content stays.
    public func update(_ model: ToolWindowModel) {
        state.model = model
        fitToContent()
        // A tool's content can change in the middle of SwiftUI's own update (typing, a field taking focus), when the
        // hosting view cannot measure yet: measure again once that update is over.
        DispatchQueue.main.async { [weak self] in self?.fitToContent() }
    }

    /// Shows the window at the wheel's centre (the pointer when there is none) as the key window, without activating
    /// Zivlet.
    public func show(at wheelCenter: CGPoint?) {
        let center = wheelCenter ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        if let visible = screen?.visibleFrame { place(at: center, visibleFrame: visible) }
        makeKeyAndOrderFront(nil)
    }

    func place(at center: CGPoint, visibleFrame: CGRect) {
        fitToContent()
        setFrame(
            ToolWindowPlacement.frame(size: frame.size, wheelCenter: center, visibleFrame: visibleFrame), display: false
        )
    }

    private func fitToContent() {
        hosting.layoutSubtreeIfNeeded()
        let measured = hosting.fittingSize.height
        // Nothing measurable (mid-update, or no model yet): keep the size the window has, never collapse to a line.
        guard measured > 1 || state.model == nil else { return }
        let height = max(1, measured)
        let top = frame.maxY
        setFrame(
            NSRect(x: frame.minX, y: top - height, width: ToolWindowView.width, height: height), display: isVisible)
    }

    /// Runs Apply when it is on and the tool is not working; true when it ran.
    @discardableResult
    func applyIfAllowed() -> Bool {
        guard state.model?.canApply == true else { return false }
        onApply()
        return true
    }

    override public func cancelOperation(_ sender: Any?) {
        onCancel()
        close()
    }

    /// Return and the keypad's Enter run Apply when nothing inside the window took them first.
    override public func keyDown(with event: NSEvent) {
        let returnKeys: Set<UInt16> = [36, 76]
        guard returnKeys.contains(event.keyCode) else { return super.keyDown(with: event) }
        applyIfAllowed()
    }

    override public func close() {
        super.close()
        state.model = nil
        state.content = nil
    }

    /// Glass unless Reduce Transparency or Increase Contrast asks for the solid surface.
    static func usesGlass(reduceTransparency: Bool, increaseContrast: Bool) -> Bool {
        !reduceTransparency && !increaseContrast
    }

    func applyDisplayOptions(reduceTransparency: Bool, increaseContrast: Bool) {
        let settings = IslandFinish.Settings(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
        state.finish = IslandFinish.floating(settings: settings)
    }

    private func watchDisplayOptions() {
        displayOptionsChanged()
        displayOptions = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayOptionsChanged() }
        }
    }

    /// The display options the finish is drawn with instead of the system's (the DEBUG screenshot flag
    /// `-ZivletIslandFinish`, so the fallbacks are captured without touching the owner's settings); nil follows the
    /// system.
    public var finishOverride: IslandFinish.Settings? {
        didSet { displayOptionsChanged() }
    }

    private func displayOptionsChanged() {
        if let finishOverride {
            return applyDisplayOptions(
                reduceTransparency: finishOverride.reduceTransparency, increaseContrast: finishOverride.increaseContrast
            )
        }
        let workspace = NSWorkspace.shared
        applyDisplayOptions(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
    }
}

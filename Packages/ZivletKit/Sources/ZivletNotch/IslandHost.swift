import AppKit
import SwiftUI
import ZivletCore
import ZivletNotchCore

/// One display's island (design/19 §5): a pre-warmed panel (D-N9), its tracking view and hosting view. It applies
/// the machine's effects and reports what happened as events through `onEvent`; it holds no island rules itself.
///
/// The frame is the current shape's bounding box (D-N4): growing sets the larger frame first and then animates the
/// shape; shrinking animates the shape and then sets the smaller frame. Every surface change bumps a generation
/// token, and a completion that finds a newer one does nothing, so a stale fade never orders out a live island and a
/// stale shrink never clips an expanded card.
public final class IslandHost {
    /// Events for this display's machine; only IslandHosts sets it.
    var onEvent: (IslandEvent) -> Void = { _ in }
    /// Each surface as it is applied, with the frame it goes to (`.zero` when hidden); for the app's log lines.
    var onSurface: (IslandSurface, CGRect) -> Void = { _, _ in }
    /// The machine's curves; IslandHosts sets them before each step.
    var curves = IslandMotion(reduceMotion: false)

    public private(set) var display: DisplayGeometry
    public private(set) var surface: IslandSurface = .hidden
    public private(set) var isPrewarmed = false

    let panel = IslandPanel()
    let chrome = IslandChromeModel()
    let client: any IslandClient
    let clock: any MonotonicClock
    let pointer: () -> CGPoint
    private let motion: IslandAnimation
    let tracking = IslandTrackingView()
    private var hosting: NSHostingView<IslandChrome>?
    let measurer = NSHostingView(rootView: AnyView(EmptyView()))

    private var contentHeight = 0.0
    private var generation = 0
    private var completion: (generation: Int, task: Task<Void, Never>)?
    /// The frame still has to shrink when the running animation completes; enter events wait until then.
    private(set) var isShrinking = false
    var deadline: (token: Int, task: Task<Void, Never>)?
    var deadlineToken = 0
    var pointerInside = false
    var lastMeasuredHeight: Double?
    private var applying = false
    private var queued: [IslandEvent] = []

    public init(
        display: DisplayGeometry, client: any IslandClient, motion: IslandAnimation = .motion,
        clock: any MonotonicClock = SystemClock(), pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.display = display
        self.client = client
        self.motion = motion
        self.clock = clock
        self.pointer = pointer
        prewarm()
    }

    public var isVisible: Bool { panel.isVisible }
    public var isKey: Bool { panel.isKeyWindow }
    public var frame: CGRect { panel.frame }
    public var hasPendingDeadline: Bool { deadline != nil }
    public var hasPendingAnimation: Bool { completion != nil }

    /// The tracking area in global points.
    var trackingRectOnScreen: CGRect? {
        tracking.trackingRect.map { $0.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY) }
    }

    /// Waits until no animation completion is pending.
    public func animationsSettled() async {
        while let pending = completion { await pending.task.value }
    }

    /// Applies one step's effects in order; events they cause are sent after the whole step.
    public func apply(_ effects: [IslandEffect]) {
        applying = true
        for effect in effects { apply(effect) }
        applying = false
        flush()
    }

    /// New geometry under the same display ID: the current surface is laid out again at once, its insets, corners
    /// and scrolling follow the new housing, and the content is measured again. A running completion was worked out
    /// for the old geometry, so it is dropped.
    public func update(display: DisplayGeometry) {
        self.display = display
        guard surface != .hidden else { return }
        generation += 1
        completion?.task.cancel()
        completion = nil
        isShrinking = false
        let target = targetFrame(surface)
        setPanelFrame(target)
        withTransaction(Transaction(animation: nil)) {
            applyShapeStyle()
            setShape(target)
        }
        contentChanged()
        checkPointer()
    }

    /// Orders out and stops every task; the host is not used again.
    public func close() {
        generation += 1
        completion?.task.cancel()
        completion = nil
        cancelDeadline()
        panel.orderOut(nil)
        surface = .hidden
    }

    func send(_ event: IslandEvent) {
        guard applying else { return onEvent(event) }
        queued.append(event)
    }

    private func flush() {
        let events = queued
        queued = []
        for event in events { onEvent(event) }
    }

    private func apply(_ effect: IslandEffect) {
        switch effect {
        case .show(let target, _, let height):
            contentHeight = height
            transition(to: target)
        case .hide: transition(to: .hidden)
        case .schedule(let at): schedule(at)
        case .cancelDeadline: cancelDeadline()
        case .held(let held): client.held(held, display: display.id, now: clock.now())
        case .becomeKey: if panel.isVisible { panel.makeKey() }
        case .becomeKeyAllowed: break
        case .resignKey: resignKey()
        case .closeRequested: client.closeRequested(display: display.id)
        }
    }

    // MARK: Surfaces

    private func transition(to target: IslandSurface) {
        generation += 1
        let mine = generation
        let previous = surface
        surface = target
        guard target != .hidden else {
            onSurface(.hidden, .zero)
            return fadeOut(mine)
        }
        refreshAccessibility()
        let goal = targetFrame(target)
        onSurface(target, goal)
        if !panel.isVisible || previous == .hidden {
            appear(at: goal, mine)
        } else {
            reshape(to: goal, mine)
        }
    }

    private func appear(at goal: CGRect, _ mine: Int) {
        setPanelFrame(goal)
        let start = NotchGeometry.housing(of: display)?.cgRect ?? goal
        let timing = motion.timing(for: curves.expand)
        withTransaction(Transaction(animation: nil)) {
            applyShapeStyle()
            applyContent()
            setShape(timing.resizes ? start : goal)
        }
        panel.orderFrontRegardless()
        animate(timing, mine) { [self] in
            setShape(goal)
            chrome.opacity = 1
        } then: {
        }
        checkPointer()
    }

    /// The new content, corners and shape move together in one animation; the old content cross-fades out.
    private func reshape(to goal: CGRect, _ mine: Int) {
        let container = panel.frame.union(goal)
        let shrinks = container != goal
        let timing = motion.timing(for: shrinks ? curves.collapse : curves.expand)
        guard timing.resizes else { return crossFade(to: goal, timing, mine) }
        if container != panel.frame { setPanelFrame(container) }
        isShrinking = shrinks
        animate(timing, mine) { [self] in
            applyShapeStyle()
            applyContent()
            setShape(goal)
            chrome.opacity = 1
        } then: { [self] in
            isShrinking = false
            guard shrinks else { return }
            let settled = targetFrame(surface)
            setPanelFrame(settled)
            setShape(settled)
            checkPointer()
        }
        checkPointer()
    }

    /// Reduce Motion (D-N5): the frame, the shape and the corners change at once; only the content cross-fades.
    private func crossFade(to goal: CGRect, _ timing: IslandAnimation.Timing, _ mine: Int) {
        isShrinking = false
        setPanelFrame(goal)
        withTransaction(Transaction(animation: nil)) {
            applyShapeStyle()
            setShape(goal)
        }
        animate(timing, mine) { [self] in
            applyContent()
            chrome.opacity = 1
        } then: {
        }
        checkPointer()
    }

    private func fadeOut(_ mine: Int) {
        cancelDeadline()
        isShrinking = false
        guard panel.isVisible else { return }
        animate(motion.timing(for: curves.collapse), mine) { [self] in
            chrome.opacity = 0
        } then: { [self] in
            panel.orderOut(nil)
            pointerInside = false
        }
    }

    /// Runs `changes` in the curve's animation, then `finish` once the animation is done, unless a newer surface
    /// change (or new geometry) came first.
    private func animate(
        _ timing: IslandAnimation.Timing, _ mine: Int,
        _ changes: () -> Void, then finish: @escaping () -> Void
    ) {
        withAnimation(timing.animation) { changes() }
        let task = Task { [weak self] in
            if timing.seconds > 0 { try? await Task.sleep(for: .seconds(timing.seconds)) }
            guard let self else { return }
            if self.completion?.generation == mine { self.completion = nil }
            guard mine == self.generation else { return }
            finish()
        }
        completion = (mine, task)
    }

    func targetFrame(_ target: IslandSurface) -> CGRect {
        IslandLayout.frame(target, on: display, contentHeight: contentHeight).cgRect
    }

    /// Resizes the panel around the shape: the shape stays where it is on screen, so growing the panel before an
    /// expansion does not move the island sideways for a frame.
    func setPanelFrame(_ rect: CGRect) {
        let drawn = drawnShapeOnScreen
        panel.setFrame(rect, display: false)
        chrome.panelSize = rect.size
        hosting?.frame = CGRect(origin: .zero, size: rect.size)
        tracking.frame = CGRect(origin: .zero, size: rect.size)
        withTransaction(Transaction(animation: nil)) { setShape(drawn) }
    }

    /// Moves the drawn shape and the tracking area to `rect` (global points). The chrome holds it from the panel's
    /// top centre, which every surface shares, so a panel resized about that centre leaves the drawing alone.
    private func setShape(_ rect: CGRect) {
        let frame = panel.frame
        let local = CGRect(x: rect.minX - frame.midX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        if chrome.shapeRect != local { chrome.shapeRect = local }
        tracking.setShape(rect.offsetBy(dx: -frame.minX, dy: -frame.minY))
    }

    /// The shape as the chrome draws it, in global points.
    var drawnShapeOnScreen: CGRect {
        let local = chrome.shapeRect
        let frame = panel.frame
        return CGRect(x: frame.midX + local.minX, y: frame.maxY - local.maxY, width: local.width, height: local.height)
    }

    /// The island group's accessibility value as the chrome holds it.
    public var accessibilityValue: String { chrome.accessibilityValue }

    /// The shape's target rectangle in global points: what the pointer is checked against.
    var shapeOnScreen: CGRect { targetFrame(surface) }

    private func prewarm() {
        let view = NSHostingView(rootView: IslandChrome(model: chrome))
        view.sizingOptions = []
        view.autoresizingMask = [.width, .height]
        tracking.addSubview(view)
        panel.contentView = tracking
        hosting = view
        wire()
        setPanelFrame(targetFrame(.collapsed))
        view.layoutSubtreeIfNeeded()
        isPrewarmed = true
    }
}

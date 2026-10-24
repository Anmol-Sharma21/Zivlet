import AppKit
import SwiftUI
import ZivletCore
import ZivletNotchCore

/// The host's inputs: deadlines on the one clock (D-N11), the pointer and the tracking area (D-N6), key changes and
/// Escape (§5.4), accessibility focus and the custom action (D-N12), and the content height (design/19 §3.4).
extension IslandHost {
    func wire() {
        panel.onEscape = { [weak self] in self?.panelEscape() }
        panel.onBecomeKey = { [weak self] in self?.panelDidBecomeKey() }
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
        tracking.onEnter = { [weak self] in self?.trackingEntered() }
        tracking.onExit = { [weak self] in self?.trackingExited() }
        accessibility.onFocus = { [weak self] in self?.accessibilityFocusChanged($0) }
        accessibility.onAction = { [weak self] in self?.performAccessibilityAction() }
    }

    // MARK: Deadlines

    /// One task per deadline: it sleeps until the deadline on the injected clock, sleeps again when it wakes early,
    /// and feeds one `.tick` to the machine. A new schedule replaces the old one.
    func schedule(_ at: Duration) {
        cancelDeadline()
        deadlineToken += 1
        let mine = deadlineToken
        let clock = self.clock
        let task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(until: at) } catch { return }
                guard let self, mine == self.deadlineToken, !Task.isCancelled else { return }
                let now = clock.now()
                guard now >= at else { continue }
                self.deadline = nil
                self.send(.tick(now: now))
                return
            }
        }
        deadline = (mine, task)
    }

    func cancelDeadline() {
        deadline?.task.cancel()
        deadline = nil
        deadlineToken += 1
    }

    // MARK: Pointer

    /// After a frame change or an order-front AppKit sends no enter or exit to a resting pointer, so the host checks.
    /// Edges count as inside: a pointer pushed against the top of the screen sits exactly on the island's top edge.
    func checkPointer() {
        let shape = shapeOnScreen
        let point = pointer()
        let onShape = (shape.minX...shape.maxX).contains(point.x) && (shape.minY...shape.maxY).contains(point.y)
        let inside = panel.isVisible && surface != .hidden && onShape
        if inside { trackingEntered() } else { trackingExited() }
    }

    func trackingEntered() {
        guard !isShrinking, !pointerInside, surface != .hidden else { return }
        pointerInside = true
        send(.pointerEntered(now: clock.now()))
    }

    func trackingExited() {
        guard pointerInside else { return }
        pointerInside = false
        send(.pointerExited(now: clock.now()))
    }

    // MARK: Keyboard and accessibility

    func panelDidBecomeKey() { send(.clicked(now: clock.now())) }
    func panelDidResignKey() { send(.resignedKey(now: clock.now())) }
    func panelEscape() { send(.escape(now: clock.now())) }

    func accessibilityFocusChanged(_ focused: Bool) {
        send(focused ? .accessibilityFocused(now: clock.now()) : .accessibilityUnfocused(now: clock.now()))
    }

    func performAccessibilityAction() { client.accessibilityActionPerformed(display: display.id) }

    /// Gives the keyboard back: a non-activating panel cannot hand key status to another app directly, so it is
    /// ordered out and in again in the same turn (no frame is drawn in between).
    func resignKey() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Content

    /// The client's content changed: the shown view is refreshed and the expanded content is measured at the card
    /// width; a new height goes to the machine.
    public func contentChanged() {
        refreshContent()
        let width = IslandLayout.Metrics.expandedWidth - 2 * flare
        measurer.rootView = AnyView(
            client.content(for: .expanded, display: display.id)
                .frame(width: width).fixedSize(horizontal: false, vertical: true))
        measurer.layoutSubtreeIfNeeded()
        let height = measurer.fittingSize.height.rounded(.up)
        // Let go of the content: a measurer that kept it would redraw off screen with every progress change.
        measurer.rootView = AnyView(EmptyView())
        guard height != lastMeasuredHeight else { return }
        lastMeasuredHeight = height
        send(.contentHeightChanged(height, now: clock.now()))
    }

    /// Everything the chrome shows, at once (a content change, new geometry).
    func refreshContent() {
        refreshAccessibility()
        applyShapeStyle()
        applyContent()
    }

    /// The island group's label, value and action: on every surface change, and whenever the client's spoken text
    /// changes (progress), so the collapsed value matches what the expanded view shows (design/19 §5.5). Only the
    /// accessibility model changes; the island is not redrawn (19b §6.2).
    func refreshAccessibility() {
        let id = display.id
        let label = client.accessibilityLabel(display: id)
        let value = client.accessibilityValue(display: id)
        let action = client.accessibilityActionName
        if accessibility.label != label { accessibility.label = label }
        if accessibility.value != value { accessibility.value = value }
        if accessibility.actionName != action { accessibility.actionName = action }
    }

    /// The surface's view; inside the transition's animation it cross-fades with the old one.
    func applyContent() {
        let shown = shownSurface
        chrome.surface = shown
        chrome.content = client.content(for: shown, display: display.id)
    }

    /// The finish, the corners, the inset under the housing and scrolling, all from the display and the settings;
    /// animated with the shape.
    func applyShapeStyle() {
        let shown = shownSurface
        chrome.finish = IslandFinish.resolve(surface, on: display, settings: finishSettings, previous: chrome.finish)
        chrome.contentTopInset = IslandLayout.contentTopInset(on: display)
        chrome.flare = flare
        chrome.topRadius = NotchGeometry.hasNotch(display) ? 0 : radius(shown)
        chrome.bottomRadius = radius(shown)
        chrome.scrolls =
            shown == .expanded && IslandLayout.contentScrolls(contentHeight: contentHeightShown, on: display)
    }

    /// While hidden (fading out) the last surface stays drawn.
    private var shownSurface: IslandSurface { surface == .hidden ? chrome.surface : surface }

    private var contentHeightShown: Double { lastMeasuredHeight ?? 0 }

    /// The flare on a notch display; the pill has none (19b D-NL4).
    var flare: Double { NotchGeometry.hasNotch(display) ? IslandLook.flare : 0 }

    private func radius(_ surface: IslandSurface) -> Double {
        if surface == .expanded { return IslandLayout.Metrics.expandedRadius }
        if NotchGeometry.hasNotch(display) {
            return surface == .toast ? IslandLayout.Metrics.toastRadius : IslandLayout.Metrics.collapsedRadius
        }
        let pill = IslandLayout.frame(surface, on: display, contentHeight: 0)
        return pill.height / 2
    }
}

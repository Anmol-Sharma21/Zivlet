/// The island's state machine (design/19 §4.1–§4.2, §5.1, §5.4). A pure value: `handling` returns the next machine and
/// the effects for the host. It knows surfaces, hover, holds, keyboard, wheel suppression and one deadline, but not
/// jobs. It reads no clock: every event carries `now`, and the host turns a `schedule` into one sleep.
public struct IslandMachine: Sendable, Equatable {
    public enum Timing {
        /// The pointer must rest this long before hover expands (a pass on the way to the menu bar opens nothing).
        public static let intent = Duration.milliseconds(150)
        /// After the pointer leaves, the card stays this long, so a brief slip does not collapse it.
        public static let grace = Duration.milliseconds(300)
    }

    public enum Hover: Sendable, Equatable {
        case outside
        case intent(until: Duration)
        case inside
        case leaving(until: Duration)
    }

    public internal(set) var request: IslandRequest?
    public internal(set) var surface: IslandSurface = .hidden
    /// The host's last measurement of the client's content.
    public internal(set) var contentHeight: Double = 0
    public internal(set) var hover: Hover = .outside
    public internal(set) var isAccessibilityFocused = false
    public internal(set) var isDragging = false
    /// Opened by the menu command or the accessibility action; the pointer passing by does not collapse it.
    public internal(set) var isPinned = false
    /// The wheel is showing (W-8): hover is ignored.
    public internal(set) var isSuppressed = false
    public internal(set) var isKeyed = false
    public internal(set) var reduceMotion = false

    public init() {}

    public var isHovered: Bool { hover == .inside }
    public var motion: IslandMotion { IslandMotion(reduceMotion: reduceMotion) }

    /// The pointer counts while it rests on the island or inside it; the grace after it leaves does not.
    public var isHeld: Bool { isPointerHolding || isAccessibilityFocused || isDragging }

    /// The pending deadline, if any (intent or grace).
    public var deadline: Duration? {
        switch hover {
        case .intent(let until), .leaving(let until): until
        case .outside, .inside: nil
        }
    }

    var isPointerHolding: Bool {
        switch hover {
        case .intent, .inside: true
        case .outside, .leaving: false
        }
    }

    var resting: IslandSurface { request?.resting ?? .hidden }
    var hoverSurface: IslandSurface { request?.hoverSurface ?? .expanded }

    /// Expanded beyond its resting surface by hover, focus, a drag or the menu command.
    var isOpenedBeyondRest: Bool { surface == hoverSurface && surface != resting && surface != .hidden }

    public func handling(_ event: IslandEvent) -> (IslandMachine, [IslandEffect]) {
        var next = self
        var effects = EffectList()
        next.apply(event, into: &effects)
        if next.isHeld != isHeld { effects.held = next.isHeld }
        return (next, effects.ordered)
    }

    private mutating func apply(_ event: IslandEvent, into effects: inout EffectList) {
        switch event {
        case .request(let request, let now): receive(request, now: now, into: &effects)
        case .contentHeightChanged(let height, _): measure(height, into: &effects)
        case .pointerEntered(let now): pointerEntered(now: now, into: &effects)
        case .pointerExited(let now): pointerExited(now: now, into: &effects)
        case .tick(let now): tick(now: now, into: &effects)
        case .accessibilityFocused: accessibilityFocused(into: &effects)
        case .accessibilityUnfocused(let now): accessibilityUnfocused(now: now, into: &effects)
        case .dragBegan: if surface != .hidden { isDragging = true }
        case .dragEnded(let now): dragEnded(now: now, into: &effects)
        case .expandRequested: expandRequested(into: &effects)
        case .clicked: clicked(into: &effects)
        case .resignedKey: isKeyed = false
        case .escape: escape(into: &effects)
        case .wheelShown: wheelShown(into: &effects)
        case .wheelHidden: isSuppressed = false
        case .reduceMotionChanged(let reduce, _): reduceMotion = reduce
        }
    }

    private mutating func receive(_ newRequest: IslandRequest?, now: Duration, into effects: inout EffectList) {
        guard let newRequest, newRequest.resting != .hidden else {
            request = nil
            if surface != .hidden, !isDragging { hide(into: &effects) }
            return
        }
        let keepsOpen = isOpenedBeyondRest && (isHovered || deadline != nil || isHeld || isPinned)
        request = newRequest
        guard !keepsOpen, surface != newRequest.resting else { return }
        show(newRequest.resting, into: &effects)
    }

    private mutating func measure(_ height: Double, into effects: inout EffectList) {
        guard height != contentHeight else { return }
        contentHeight = height
        if surface == .expanded { show(.expanded, into: &effects) }
    }

    mutating func show(_ target: IslandSurface, into effects: inout EffectList) {
        surface = target
        effects.surface = .show(target, display: request?.display ?? 0, contentHeight: contentHeight)
    }

    /// Ordered out, timers cleared, focus and pins gone; the keyboard goes back to the person's app.
    mutating func hide(into effects: inout EffectList) {
        surface = .hidden
        hover = .outside
        isAccessibilityFocused = false
        isDragging = false
        isPinned = false
        effects.surface = .hide
        effects.deadline = .cancelDeadline
        if isKeyed {
            isKeyed = false
            effects.key = .resignKey
        }
    }
}

/// The effects of one step in a fixed order: surface, deadline, hold, keyboard, close. One slot each, so a step
/// never carries two deadlines.
struct EffectList {
    var surface: IslandEffect?
    var deadline: IslandEffect?
    var held: Bool?
    var key: IslandEffect?
    var close: IslandEffect?

    var ordered: [IslandEffect] {
        [surface, deadline, held.map(IslandEffect.held), key, close].compactMap { $0 }
    }
}

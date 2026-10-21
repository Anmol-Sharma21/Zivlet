/// Everything the island machine reacts to (design/19 §4.2). Each event carries its own monotonic time, so the
/// machine never reads a clock. Display changes are not events: `IslandHosts` owns them (§5.2).
public enum IslandEvent: Sendable, Equatable {
    case request(IslandRequest?, now: Duration)
    case contentHeightChanged(Double, now: Duration)
    case pointerEntered(now: Duration)
    case pointerExited(now: Duration)
    case accessibilityFocused(now: Duration)
    case accessibilityUnfocused(now: Duration)
    case dragBegan(now: Duration)
    case dragEnded(now: Duration)
    case expandRequested(now: Duration)
    case tick(now: Duration)
    case clicked(now: Duration)
    case resignedKey(now: Duration)
    case escape(now: Duration)
    case wheelShown(now: Duration)
    case wheelHidden(now: Duration)
    case reduceMotionChanged(Bool, now: Duration)

    /// One case per event, so a table can require a row for every event.
    public enum Kind: String, Sendable, CaseIterable, CustomStringConvertible {
        case request, contentHeightChanged, pointerEntered, pointerExited, accessibilityFocused
        case accessibilityUnfocused, dragBegan, dragEnded, expandRequested, tick, clicked, resignedKey, escape
        case wheelShown, wheelHidden, reduceMotionChanged

        public var description: String { rawValue }
    }

    public var kind: Kind { parts.kind }
    public var now: Duration { parts.now }

    /// One sample of every kind at `now` (the request withdraws); new kinds join automatically.
    public static func allCases(now: Duration) -> [IslandEvent] {
        Kind.allCases.map { sample($0, now: now) }
    }

    private static func sample(_ kind: Kind, now: Duration) -> IslandEvent {
        switch kind {
        case .request: .request(nil, now: now)
        case .contentHeightChanged: .contentHeightChanged(200, now: now)
        case .pointerEntered: .pointerEntered(now: now)
        case .pointerExited: .pointerExited(now: now)
        case .accessibilityFocused: .accessibilityFocused(now: now)
        case .accessibilityUnfocused: .accessibilityUnfocused(now: now)
        case .dragBegan: .dragBegan(now: now)
        case .dragEnded: .dragEnded(now: now)
        case .expandRequested: .expandRequested(now: now)
        case .tick: .tick(now: now)
        case .clicked: .clicked(now: now)
        case .resignedKey: .resignedKey(now: now)
        case .escape: .escape(now: now)
        case .wheelShown: .wheelShown(now: now)
        case .wheelHidden: .wheelHidden(now: now)
        case .reduceMotionChanged: .reduceMotionChanged(true, now: now)
        }
    }

    private var parts: (kind: Kind, now: Duration) {
        switch self {
        case .request(_, let now): (.request, now)
        case .contentHeightChanged(_, let now): (.contentHeightChanged, now)
        case .pointerEntered(let now): (.pointerEntered, now)
        case .pointerExited(let now): (.pointerExited, now)
        case .accessibilityFocused(let now): (.accessibilityFocused, now)
        case .accessibilityUnfocused(let now): (.accessibilityUnfocused, now)
        case .dragBegan(let now): (.dragBegan, now)
        case .dragEnded(let now): (.dragEnded, now)
        case .expandRequested(let now): (.expandRequested, now)
        case .tick(let now): (.tick, now)
        case .clicked(let now): (.clicked, now)
        case .resignedKey(let now): (.resignedKey, now)
        case .escape(let now): (.escape, now)
        case .wheelShown(let now): (.wheelShown, now)
        case .wheelHidden(let now): (.wheelHidden, now)
        case .reduceMotionChanged(_, let now): (.reduceMotionChanged, now)
        }
    }
}

/// What the host must do after an event. At most one deadline effect per step (D-N11: one sleep on one clock).
public enum IslandEffect: Sendable, Equatable, Hashable {
    case show(IslandSurface, display: UInt32, contentHeight: Double)
    case hide
    case schedule(Duration)
    case cancelDeadline
    /// The combined hold (pointer, accessibility focus, a drag from the island) changed; the client pauses or restarts
    /// its lingers (D-N13).
    case held(Bool)
    case becomeKey
    case becomeKeyAllowed
    case resignKey
    case closeRequested(IslandClientID)
}

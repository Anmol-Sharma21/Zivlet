import ZivletCore

/// 03a §1.3. Associated values are immutable; every step builds new values.
public enum TriggerState: Sendable, Equatable {
    case idle
    case pressed(snapshot: Int, held: ModifierMask)
    case detecting(snapshot: Int, held: ModifierMask, deadline: Duration)
    case passive
    case live(Live)
    case wheel(Wheel)
    case releasing(mode: WheelMode, deadline: Duration)

    /// File drag detected, no wheel. `summary` is nil while the payload probe runs.
    public struct Live: Sendable, Equatable {
        public let changeCount: Int
        public let summary: DragSummary?
        public let previous: ModifierMask
        public let liveStart: Duration
        public let pendingEdge: Bool
        public let queued: WheelMode?
        public let location: Point2D

        func observing(_ s: InputSample, pendingEdge: Bool) -> Live {
            Live(
                changeCount: changeCount, summary: summary, previous: s.modifiers, liveStart: liveStart,
                pendingEdge: pendingEdge, queued: queued, location: s.location)
        }

        func queueing(_ mode: WheelMode) -> Live {
            Live(
                changeCount: changeCount, summary: summary, previous: previous, liveStart: liveStart,
                pendingEdge: pendingEdge, queued: mode, location: location)
        }

        func receiving(_ summary: DragSummary) -> Live {
            Live(
                changeCount: changeCount, summary: summary, previous: previous, liveStart: liveStart,
                pendingEdge: pendingEdge, queued: nil, location: location)
        }
    }

    /// Wheel visible; `anchor` never follows the pointer.
    public struct Wheel: Sendable, Equatable {
        public let mode: WheelMode
        public let changeCount: Int
        public let summary: DragSummary
        public let previous: ModifierMask
        public let anchor: Point2D

        func with(mode: WheelMode? = nil, previous: ModifierMask) -> Wheel {
            Wheel(
                mode: mode ?? self.mode, changeCount: changeCount, summary: summary, previous: previous,
                anchor: anchor)
        }
    }
}

public struct TriggerStep: Sendable, Equatable {
    public let next: TriggerMachine
    public let effects: [TriggerEffect]
}

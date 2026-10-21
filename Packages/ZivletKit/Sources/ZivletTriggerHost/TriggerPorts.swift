import ZivletCore
import ZivletTrigger

/// OS events the host can ask to be woken by (03a §1.3).
public enum MonitoredEvent: String, Sendable, Hashable, CaseIterable {
    case mouseDown, mouseDragged, mouseUp, flagsChanged

    public var source: SampleSource {
        switch self {
        case .mouseDown: .mouseDown
        case .mouseDragged: .mouseDragged
        case .mouseUp: .mouseUp
        case .flagsChanged: .flagsChanged
        }
    }
}

/// Everything the OS layer should be doing right now. The host recomputes it after each step and applies it only
/// when it changes, so the OS layer never sees duplicate requests.
public struct SamplingPlan: Sendable, Equatable {
    public let events: Set<MonitoredEvent>
    /// Display-rate sampler: only while a drag is detected, live or showing the wheel.
    public let sampling: Bool
    /// 2 Hz button watchdog: only in `pressed` and `passive` (03a §1.5).
    public let watchdog: Bool
    /// Esc hotkey: only while the wheel is visible (03a §1.8).
    public let escapeHotkey: Bool

    public init(
        events: Set<MonitoredEvent>, sampling: Bool = false, watchdog: Bool = false, escapeHotkey: Bool = false
    ) {
        self.events = events
        self.sampling = sampling
        self.watchdog = watchdog
        self.escapeHotkey = escapeHotkey
    }

    public static let off = SamplingPlan(events: [])
}

/// What the OS layer reports back to the host.
public enum TriggerSignal: Sendable, Equatable {
    case event(SampleSource)
    case escape
    case spaceChanged
    case dropHandled
}

/// Every OS read the host makes, behind one protocol so the host logic runs against a fake in tests.
public protocol InputReading: AnyObject {
    var uptime: Duration { get }
    var modifiers: ModifierMask { get }
    var primaryButtonDown: Bool { get }
    var dragChangeCount: Int { get }
    var location: Point2D { get }
    var pointerInsideWheel: Bool { get }
    /// Types only: file URLs or file promises on the drag pasteboard. Never reads URLs or data (14 §1.3).
    func dragHasFileTypes() -> Bool
}

/// Monitors, sampler, watchdog and hotkey. Calls `onSignal` on the main actor.
public protocol TriggerScheduling: AnyObject {
    var onSignal: ((TriggerSignal) -> Void)? { get set }
    func apply(_ plan: SamplingPlan)
}

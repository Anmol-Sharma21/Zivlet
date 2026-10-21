import ZivletCore

/// Which host event produced an input sample (03a §1.2).
public enum SampleSource: String, Sendable, Codable {
    case mouseDown, mouseDragged, mouseUp, frame, flagsChanged
}

/// One snapshot of the inputs the machine reads. The host builds it; the machine never polls.
public struct InputSample: Sendable, Equatable, Codable {
    public let uptime: Duration
    public let source: SampleSource
    public let modifiers: ModifierMask
    public let primaryButtonDown: Bool
    public let dragChangeCount: Int
    public let dragHasFileTypes: Bool
    public let location: Point2D
    public let pointerInsideWheel: Bool

    public init(
        uptime: Duration, source: SampleSource, modifiers: ModifierMask = [], primaryButtonDown: Bool,
        dragChangeCount: Int, dragHasFileTypes: Bool = false, location: Point2D = .zero,
        pointerInsideWheel: Bool = false
    ) {
        self.uptime = uptime
        self.source = source
        self.modifiers = modifiers
        self.primaryButtonDown = primaryButtonDown
        self.dragChangeCount = dragChangeCount
        self.dragHasFileTypes = dragHasFileTypes
        self.location = location
        self.pointerInsideWheel = pointerInsideWheel
    }
}

/// What the dragged items allow. Built by the host probe once per change count.
public struct DragSummary: Sendable, Equatable, Codable {
    public let itemCount: Int
    public let acceptedModes: Set<WheelMode>

    public init(itemCount: Int, acceptedModes: Set<WheelMode>) {
        self.itemCount = itemCount
        self.acceptedModes = acceptedModes
    }
}

/// Everything the machine reacts to.
public enum TriggerEvent: Sendable, Equatable {
    case sample(InputSample)
    case payload(changeCount: Int, summary: DragSummary)
    case escape
    case spaceChanged
    case dropHandled
}

/// Why a wheel was hidden.
public enum HideReason: String, Sendable, Codable {
    case sameModifierRetap, escape, buttonUp, lingerExpired, spaceChanged, dropped
}

/// Why a switch to another wheel was refused.
public enum RejectReason: String, Sendable, Codable {
    case noItemsForMode
}

/// Instructions for the host. Host effects are idempotent.
public enum TriggerEffect: Sendable, Equatable {
    case installDragMonitors, removeDraggedMonitor, removeDragMonitors, startSampler, stopSampler
    case probePayload(changeCount: Int)
    case show(WheelMode, at: Point2D)
    case switchTo(WheelMode)
    case reject(WheelMode, RejectReason)
    case hide(HideReason)
}

/// Tunable numbers and bindings (03a §1.5). Defaults are the Zivlet values.
public struct TriggerConfig: Sendable, Equatable {
    public let bindings: TriggerBindings
    public let honorsModifierHeldAtDragStart: Bool
    public let retapClosesWheel: Bool
    public let detectionWindow: Duration
    public let edgeDebounce: Duration
    public let releaseTimeout: Duration

    public init(
        bindings: TriggerBindings = .standard, honorsModifierHeldAtDragStart: Bool = false,
        retapClosesWheel: Bool = true, detectionWindow: Duration = .milliseconds(300),
        edgeDebounce: Duration = .milliseconds(40), releaseTimeout: Duration = .milliseconds(150)
    ) {
        self.bindings = bindings
        self.honorsModifierHeldAtDragStart = honorsModifierHeldAtDragStart
        self.retapClosesWheel = retapClosesWheel
        self.detectionWindow = detectionWindow
        self.edgeDebounce = edgeDebounce
        self.releaseTimeout = releaseTimeout
    }
}

import ZivletCore

/// The last 50 trigger transitions, for Copy Diagnostics (P1-48). Only steps that change the state's kind or emit
/// effects are kept, so 120 Hz frame samples do not push the interesting ones out. Entries hold names only: no
/// files, paths or drag contents. Immutable: `recording` returns a new trace.
public struct TriggerTrace: Sendable, Equatable {
    public static let capacity = 50

    public struct Entry: Sendable, Equatable {
        public let uptime: Duration
        public let event: String
        public let from: String
        public let to: String
        public let effects: [String]

        public init(uptime: Duration, event: String, from: String, to: String, effects: [String]) {
            self.uptime = uptime
            self.event = event
            self.from = from
            self.to = to
            self.effects = effects
        }

        /// "+12.345 s  sample.frame  live → wheel  [show]"
        public var line: String {
            let millis = uptime.components.seconds * 1_000 + uptime.components.attoseconds / 1_000_000_000_000_000
            let seconds = "\(millis / 1_000).\(String(millis % 1_000).leftPadded(to: 3))"
            return "+\(seconds) s  \(event)  \(from) → \(to)  [\(effects.joined(separator: ", "))]"
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = Array(entries.suffix(Self.capacity))
    }

    public func recording(_ entry: Entry) -> TriggerTrace {
        TriggerTrace(entries: entries + [entry])
    }

    public var lines: [String] { entries.map(\.line) }

    /// The entry for one step, or nil when it changed nothing worth keeping. `uptime` defaults to the sample's.
    public static func entry(event: TriggerEvent, from: TriggerState, step: TriggerStep, uptime: Duration? = nil)
        -> Entry?
    {
        let to = step.next.state.name
        guard to != from.name || !step.effects.isEmpty else { return nil }
        return Entry(
            uptime: uptime ?? event.uptime ?? .zero, event: event.name, from: from.name, to: to,
            effects: step.effects.map(\.name))
    }
}

extension TriggerState {
    public var name: String {
        switch self {
        case .idle: "idle"
        case .pressed: "pressed"
        case .detecting: "detecting"
        case .passive: "passive"
        case .live: "live"
        case .wheel: "wheel"
        case .releasing: "releasing"
        }
    }
}

extension TriggerEvent {
    public var name: String {
        switch self {
        case .sample(let sample): "sample.\(sample.source.rawValue)"
        case .payload: "payload"
        case .escape: "escape"
        case .spaceChanged: "spaceChanged"
        case .dropHandled: "dropHandled"
        }
    }

    var uptime: Duration? {
        if case .sample(let sample) = self { return sample.uptime }
        return nil
    }
}

extension TriggerEffect {
    public var name: String {
        switch self {
        case .installDragMonitors: "installDragMonitors"
        case .removeDraggedMonitor: "removeDraggedMonitor"
        case .removeDragMonitors: "removeDragMonitors"
        case .startSampler: "startSampler"
        case .stopSampler: "stopSampler"
        case .probePayload: "probePayload"
        case .show: "show"
        case .switchTo: "switchTo"
        case .reject: "reject"
        case .hide: "hide"
        }
    }
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String {
        String(repeating: "0", count: max(0, width - count)) + self
    }
}

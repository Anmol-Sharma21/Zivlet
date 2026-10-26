/// How a proximity rule does on a set of traces (P2-197): the share of `notch` traces that opened the tray, and the
/// number of `normal` traces that opened it although they should not.
public struct ProximityScore: Sendable, Equatable {
    public let notchBound: Int
    public let detected: Int
    public let normal: Int
    public let accidental: Int

    public init(notchBound: Int, detected: Int, normal: Int, accidental: Int) {
        self.notchBound = notchBound
        self.detected = detected
        self.normal = normal
        self.accidental = accidental
    }

    /// Detected over notch-bound traces; 0 when there are none, so an empty set never passes.
    public var detection: Double { notchBound == 0 ? 0 : Double(detected) / Double(notchBound) }

    /// The P2-197 bar on this set alone: at least 95 % detected and no accidental opens.
    public var meetsTheBar: Bool { detection >= 0.95 && accidental == 0 }
}

/// Runs the proximity rule over traces. Each trace gets the zones of its own display from `zones`, so recordings
/// from different displays replay against their own geometry.
public enum TraceEvaluator {
    public static func score(
        _ traces: [DragTrace], zones: (TraceDisplay) -> [NotchProximity.Zone], config: NotchProximity.Config
    ) -> ProximityScore {
        let opened = traces.map { opens($0, zones: zones($0.display), config: config) }
        let pairs = zip(traces.map(\.label), opened)
        return ProximityScore(
            notchBound: traces.filter { $0.label == .notch }.count,
            detected: pairs.filter { $0 == .notch && $1 }.count,
            normal: traces.filter { $0.label == .normal }.count,
            accidental: pairs.filter { $0 == .normal && $1 }.count)
    }

    /// Whether the rule enters at any point of the trace's live samples.
    public static func opens(_ trace: DragTrace, zones: [NotchProximity.Zone], config: NotchProximity.Config)
        -> Bool
    {
        NotchProximity(zones: zones, config: config).events(for: trace.inputSamples).contains {
            if case .entered = $0 { return true }
            return false
        }
    }
}

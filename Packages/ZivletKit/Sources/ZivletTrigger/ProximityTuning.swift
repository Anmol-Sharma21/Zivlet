/// Every combination of proximity constants over a set of traces, best first (NB5, OS-M5b-1): fewest accidental opens,
/// then highest detection. The owner runs it on recorded drags with `zivlet-traces tune <folder>` when the replay
/// fails, and the best row becomes `NotchProximity.Config.provisional` in one commit.
public enum ProximityTuning {
    public struct Grid: Sendable, Equatable {
        public let margins: [Double]
        public let dwells: [Duration]
        /// nil is "no speed limit".
        public let speeds: [Double?]

        public init(margins: [Double], dwells: [Duration], speeds: [Double?]) {
            self.margins = margins
            self.dwells = dwells
            self.speeds = speeds
        }
    }

    /// Margins 0–80 pt, dwells 0–200 ms, speeds 400, 800, 1600 pt/s and none: 100 rows.
    public static let standard = Grid(
        margins: [0, 20, 40, 60, 80], dwells: [0, 50, 100, 150, 200].map { .milliseconds($0) },
        speeds: [400, 800, 1600, nil])

    public struct Row: Sendable, Equatable {
        public let config: NotchProximity.Config
        public let score: ProximityScore

        public init(config: NotchProximity.Config, score: ProximityScore) {
            self.config = config
            self.score = score
        }

        /// "margin 30 pt  dwell 240 ms  speed 600 pt/s  detection 98.0 % (49/50)  accidental 0/200"
        public var line: String {
            let speed = config.maxSpeed.map { "\(Int($0.rounded())) pt/s" } ?? "none"
            let tenths = Int((score.detection * 1_000).rounded())
            return "margin \(Int(config.margin.rounded())) pt  dwell \(Self.milliseconds(config.dwell)) ms  "
                + "speed \(speed)  detection \(tenths / 10).\(tenths % 10) % (\(score.detected)/\(score.notchBound))  "
                + "accidental \(score.accidental)/\(score.normal)"
        }

        private static func milliseconds(_ duration: Duration) -> Int64 {
            duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000
        }
    }

    public static func grid(
        traces: [DragTrace], margins: [Double], dwells: [Duration], speeds: [Double?],
        release: Double = NotchProximity.Config.provisional.release,
        zones: (TraceDisplay, Double) -> [NotchProximity.Zone]
    ) -> [Row] {
        let configs = margins.flatMap { margin in
            dwells.flatMap { dwell in
                speeds.map { NotchProximity.Config(margin: margin, dwell: dwell, maxSpeed: $0, release: release) }
            }
        }
        let rows = configs.map { config in
            Row(
                config: config, score: TraceEvaluator.score(traces, zones: { zones($0, config.margin) }, config: config)
            )
        }
        return rows.enumerated().sorted { a, b in
            if a.element.score.accidental != b.element.score.accidental {
                return a.element.score.accidental < b.element.score.accidental
            }
            if a.element.score.detection != b.element.score.detection {
                return a.element.score.detection > b.element.score.detection
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    public static func grid(
        traces: [DragTrace], _ grid: Grid = standard, zones: (TraceDisplay, Double) -> [NotchProximity.Zone]
    ) -> [Row] {
        self.grid(traces: traces, margins: grid.margins, dwells: grid.dwells, speeds: grid.speeds, zones: zones)
    }
}

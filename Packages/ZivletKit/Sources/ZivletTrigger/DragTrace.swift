import ZivletCore

/// One recorded (or made-up) file drag for the proximity and shake replays (P2-197, D-M5b-10): timings, positions,
/// the button and the display's geometry, nothing about files. Built and decoded through the same checks, because a
/// trace file is outside data: schema 1, a known label, 2…20,000 samples, finite numbers, time never going back,
/// every point within the display widened by 100 pt, and not cut short by the recorder's cap.
public struct DragTrace: Sendable, Equatable, Codable {
    public static let schemaVersion = 1
    public static let sampleLimits = 2...20_000
    /// How far outside the display a sample may be (the pointer can sit on a neighbouring display's edge).
    public static let displaySlack = 100.0

    public enum Label: String, Sendable, Equatable, Codable, CaseIterable {
        /// An everyday drag that must not open the tray.
        case normal
        /// A drag aimed at the notch that must open it.
        case notch
    }

    /// One live sample: `t` in milliseconds from any origin, the position in global points (y up), the button.
    public struct Sample: Sendable, Equatable, Codable {
        public let t: Double
        public let x: Double
        public let y: Double
        public let down: Bool

        public init(t: Double, x: Double, y: Double, down: Bool) {
            self.t = t
            self.x = x
            self.y = y
            self.down = down
        }
    }

    public let schema: Int
    public let label: Label
    public let display: TraceDisplay
    /// The macOS version string, so a replay can tell recordings from different systems apart.
    public let os: String
    public let samples: [Sample]
    /// The recorder hit its sample cap and dropped the rest; such a trace is refused.
    public let truncated: Bool

    public init(
        label: Label, display: TraceDisplay, os: String, samples: [Sample], truncated: Bool = false,
        schema: Int = DragTrace.schemaVersion
    ) throws(DragTraceError) {
        try Self.check(schema: schema, display: display, samples: samples, truncated: truncated)
        self.schema = schema
        self.label = label
        self.display = display
        self.os = os
        self.samples = samples
        self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey {
        case schema, label, display, os, samples, truncated
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try c.decode(Int.self, forKey: .schema)
        guard schema == Self.schemaVersion else { throw DragTraceError.unsupportedSchema(schema) }
        let name = try c.decode(String.self, forKey: .label)
        guard let label = Label(rawValue: name) else { throw DragTraceError.unknownLabel(name) }
        try self.init(
            label: label, display: try c.decode(TraceDisplay.self, forKey: .display),
            os: try c.decode(String.self, forKey: .os), samples: try c.decode([Sample].self, forKey: .samples),
            truncated: try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false, schema: schema)
    }

    /// The samples with the button down, as the live frame samples the detectors take.
    public var inputSamples: [InputSample] {
        samples.filter(\.down).map {
            InputSample(
                uptime: .nanoseconds(Int64(($0.t * 1e6).rounded())), source: .frame, primaryButtonDown: true,
                dragChangeCount: 1, dragHasFileTypes: true, location: Point2D(x: $0.x, y: $0.y))
        }
    }

    private static func check(schema: Int, display: TraceDisplay, samples: [Sample], truncated: Bool)
        throws(DragTraceError)
    {
        guard schema == schemaVersion else { throw .unsupportedSchema(schema) }
        guard !truncated else { throw .truncated }
        guard sampleLimits.contains(samples.count) else { throw .sampleCount(samples.count) }
        try display.check()
        let bounds = display.frame.widened(by: displaySlack)
        var previous = -Double.infinity
        for (index, sample) in samples.enumerated() {
            guard sample.t.isFinite, sample.x.isFinite, sample.y.isFinite else { throw .notFinite(sample: index) }
            guard sample.t >= previous else { throw .timeGoesBack(sample: index) }
            guard bounds.containsClosed(Point2D(x: sample.x, y: sample.y)) else {
                throw .outsideDisplay(sample: index)
            }
            previous = sample.t
        }
    }
}

/// The display a trace was made on, as plain rectangles (global points, y up), so this module needs no notch types.
public struct TraceDisplay: Sendable, Equatable, Codable {
    public let id: UInt32
    public let frame: Rect2D
    public let visibleFrame: Rect2D
    public let safeAreaTop: Double
    public let auxiliaryTopLeft: Rect2D?
    public let auxiliaryTopRight: Rect2D?

    public init(
        id: UInt32, frame: Rect2D, visibleFrame: Rect2D, safeAreaTop: Double, auxiliaryTopLeft: Rect2D?,
        auxiliaryTopRight: Rect2D?
    ) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    func check() throws(DragTraceError) {
        let rects = [frame, visibleFrame] + [auxiliaryTopLeft, auxiliaryTopRight].compactMap { $0 }
        let numbers = rects.flatMap { [$0.x, $0.y, $0.width, $0.height] } + [safeAreaTop]
        guard numbers.allSatisfy(\.isFinite) else { throw .badDisplay }
        guard frame.width > 0, frame.height > 0, safeAreaTop >= 0 else { throw .badDisplay }
    }
}

/// Why a trace was refused. The text names the rule and a sample index, never a path or a name.
public enum DragTraceError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case unknownLabel(String)
    case sampleCount(Int)
    case notFinite(sample: Int)
    case timeGoesBack(sample: Int)
    case outsideDisplay(sample: Int)
    case badDisplay
    case truncated

    public var description: String {
        switch self {
        case .unsupportedSchema(let schema): "Trace schema \(schema) is not supported; this build reads schema 1"
        case .unknownLabel: "Trace label must be \"normal\" or \"notch\""
        case .sampleCount(let count):
            "Trace has \(count) samples; it needs \(DragTrace.sampleLimits.lowerBound) to "
                + "\(DragTrace.sampleLimits.upperBound)"
        case .notFinite(let index): "Sample \(index) has a value that is not a finite number"
        case .timeGoesBack(let index): "Sample \(index) is earlier than the one before it"
        case .outsideDisplay(let index): "Sample \(index) is more than 100 pt outside the trace's display"
        case .badDisplay: "The trace's display values are not usable"
        case .truncated: "The recorder stopped this trace at its sample limit, so it is incomplete"
        }
    }
}

extension Rect2D {
    func widened(by inset: Double) -> Rect2D {
        Rect2D(x: x - inset, y: y - inset, width: width + 2 * inset, height: height + 2 * inset)
    }

    /// Like `contains`, but the max edges count as inside (a pointer pinned to the top edge is on the display).
    func containsClosed(_ p: Point2D) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
}

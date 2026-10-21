import ZivletCore
import ZivletEngineKit

/// One ffmpeg invocation and its share of the job's progress. Invariant: non-empty argv, finite weight > 0.
public struct FFmpegPass: Sendable, Codable, Equatable {
    public let argv: [String]
    public let weight: Double

    public init(argv: [String], weight: Double) throws(MediaPlanError) {
        guard !argv.isEmpty, weight.isFinite, weight > 0 else { throw .invalidPass }
        self.argv = argv
        self.weight = weight
    }

    /// A planner's single pass: the argv always starts with the fixed prefix, so it is never empty.
    fileprivate init(wholeJob argv: [String]) {
        self.argv = argv
        self.weight = 1
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let argv = try c.decode([String].self, forKey: .argv)
        let weight = try c.decode(Double.self, forKey: .weight)
        do { try self.init(argv: argv, weight: weight) } catch { throw invalid(error, decoder) }
    }
}

/// One planned ffmpeg job: its passes in order, the expected duration and the scheduler lane (03b §5.2).
/// Invariant: at least one pass.
public struct FFmpegPlan: Sendable, Codable, Equatable {
    public let passes: [FFmpegPass]
    public let expectedDurationMicros: Int64?
    public let lane: Lane

    public init(passes: [FFmpegPass], expectedDurationMicros: Int64?, lane: Lane) throws(MediaPlanError) {
        guard !passes.isEmpty else { throw .invalidPass }
        self.passes = passes
        self.expectedDurationMicros = expectedDurationMicros
        self.lane = lane
    }

    /// The planners' shape: one pass with weight 1.
    init(single argv: [String], expectedDurationMicros: Int64?, lane: Lane) {
        self.passes = [FFmpegPass(wholeJob: argv)]
        self.expectedDurationMicros = expectedDurationMicros
        self.lane = lane
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let passes = try c.decode([FFmpegPass].self, forKey: .passes)
        let duration = try c.decodeIfPresent(Int64.self, forKey: .expectedDurationMicros)
        let lane = try c.decode(Lane.self, forKey: .lane)
        do {
            try self.init(passes: passes, expectedDurationMicros: duration, lane: lane)
        } catch {
            throw invalid(error, decoder)
        }
    }
}

/// A plan-model violation found while decoding, reported as `DecodingError` like any other bad payload.
private func invalid(_ error: MediaPlanError, _ decoder: any Decoder) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid plan", underlyingError: error))
}

/// The user option a value was refused for.
public enum MediaOption: String, Sendable, Equatable { case heightLimit, gifFPS, gifWidthLimit }

/// Why a media request cannot be planned.
public enum MediaPlanError: Error, Equatable, Sendable {
    case pairNotSupported(FormatID, FormatID)
    case noAudioTrack
    case noVideoTrack
    case invalidPath(String)
    case invalidOption(MediaOption, Int)
    /// A pass with an empty argv or a weight that is not finite and positive, or a plan without passes.
    case invalidPass
}

/// Everything a planner needs: absolute paths, the sniffed source format, the probe, target and options.
public struct MediaPlanRequest: Sendable, Equatable {
    public let source: String
    public let sourceFormat: FormatID
    public let info: MediaInfo
    public let target: FormatID
    /// Absolute path of the staged output the runtime moves into place after success.
    public let staged: String
    public let options: MediaOptions
    public let capabilities: MediaCapabilities

    /// `options: nil` takes `MediaOptions.defaults(for: target)`.
    public init(
        source: String, sourceFormat: FormatID, info: MediaInfo, target: FormatID, staged: String,
        options: MediaOptions? = nil, capabilities: MediaCapabilities = MediaCapabilities()
    ) {
        self.source = source
        self.sourceFormat = sourceFormat
        self.info = info
        self.target = target
        self.staged = staged
        self.options = options ?? .defaults(for: target)
        self.capabilities = capabilities
    }
}

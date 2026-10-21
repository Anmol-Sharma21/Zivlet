import Foundation
import ZivletCore

/// One ffmpeg invocation: the complete argv (the runner prepends nothing) and the duration progress is measured
/// against (`nil` = indeterminate).
public struct FFmpegStage: Sendable, Codable, Equatable {
    public let argv: [String]
    public let expectedDurationMicros: Int64?

    public init(argv: [String], expectedDurationMicros: Int64?) {
        self.argv = argv
        self.expectedDurationMicros = expectedDurationMicros
    }
}

/// One step of a plan (02 §7.3). M3 executors: ffmpeg and the ImageIO pipeline.
public enum Stage: Sendable, Codable, Equatable {
    case ffmpeg(FFmpegStage)
    case image(ImagePipelineSpec)

    /// The ffmpeg payload, or nil for another executor.
    public var ffmpeg: FFmpegStage? {
        guard case .ffmpeg(let stage) = self else { return nil }
        return stage
    }

    /// The ImageIO payload, or nil for another executor.
    public var image: ImagePipelineSpec? {
        guard case .image(let spec) = self else { return nil }
        return spec
    }
}

/// Something the result card tells the user about the output (10 §4.2: "Animation flattened to first frame").
/// `svgRasterizedInPDF`: an SVG became a PDF page holding a picture of it, not vector art (D-M4-6).
public enum PlanNote: String, Sendable, Codable, Equatable {
    case alphaFlattened, firstFrameOnly, svgRasterizedInPDF
}

public enum PlanError: Error, Equatable, Sendable {
    case noStages, countMismatch, badWeights, noFrames, badQuality, badMethod, badScale
}

/// A pure, Codable plan (02 §7.3, ADR-06): stages with progress weights and one scheduler lane each, the output
/// format and the hidden staged file it writes. Invariant: at least one stage; stages, weights and lanes line up;
/// weights are finite, positive and sum to 1.
public struct ExecutionPlan: Sendable, Codable, Equatable {
    static let weightTolerance = 1e-9

    public let engine: EngineID
    public let stages: [Stage]
    public let stageWeights: [Double]
    public let lanes: [Lane]
    public let outputFormat: FormatID
    public let stagedFile: URL
    public let notes: [PlanNote]

    public init(
        engine: EngineID, stages: [Stage], stageWeights: [Double], lanes: [Lane], outputFormat: FormatID,
        stagedFile: URL, notes: [PlanNote] = []
    ) throws(PlanError) {
        guard !stages.isEmpty else { throw .noStages }
        guard stageWeights.count == stages.count, lanes.count == stages.count else { throw .countMismatch }
        let positive = stageWeights.allSatisfy { $0.isFinite && $0 > 0 }
        guard positive, abs(stageWeights.reduce(0, +) - 1) <= Self.weightTolerance else { throw .badWeights }
        self.engine = engine
        self.stages = stages
        self.stageWeights = stageWeights
        self.lanes = lanes
        self.outputFormat = outputFormat
        self.stagedFile = stagedFile
        self.notes = notes
    }

    /// Job fraction when `stage` (0-based) is `fraction` done: earlier stages count in full.
    public func overallFraction(stage: Int, fraction: Double) -> Double {
        let done = stageWeights.prefix(stage).reduce(0, +)
        return min(1, done + stageWeights[stage] * min(1, max(0, fraction)))
    }
}

extension ExecutionPlan {
    private enum CodingKeys: String, CodingKey {
        case engine, stages, stageWeights, lanes, outputFormat, stagedFile, notes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                engine: c.decode(EngineID.self, forKey: .engine), stages: c.decode([Stage].self, forKey: .stages),
                stageWeights: c.decode([Double].self, forKey: .stageWeights),
                lanes: c.decode([Lane].self, forKey: .lanes),
                outputFormat: c.decode(FormatID.self, forKey: .outputFormat),
                stagedFile: c.decode(URL.self, forKey: .stagedFile), notes: c.decode([PlanNote].self, forKey: .notes))
        } catch let error as PlanError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Invalid plan", underlyingError: error))
        }
    }
}

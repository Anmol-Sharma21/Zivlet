import Foundation
import Synchronization
import Testing
import ZivletCore

@testable import ZivletEngineKit

@Suite("Execution plans and progress sinks (P1-01, 02 §7.3, 03a §4.5)")
struct ExecutionPlanTests {
    static let staged = URL(fileURLWithPath: "/out/.zivlet-1.mp4")

    static func stage(_ argv: String) -> Stage { .ffmpeg(FFmpegStage(argv: [argv], expectedDurationMicros: 1_000)) }

    static func plan(weights: [Double], lanes: [Lane]? = nil) throws -> ExecutionPlan {
        try ExecutionPlan(
            engine: .media, stages: weights.indices.map { stage("pass\($0)") }, stageWeights: weights,
            lanes: lanes ?? weights.map { _ in .audio }, outputFormat: .mp4, stagedFile: staged)
    }

    @Test func aValidPlanRoundTripsThroughJSON() throws {
        let plan = try Self.plan(weights: [0.35, 0.65], lanes: [.swVideo, .swVideo])
        #expect(try JSONDecoder().decode(ExecutionPlan.self, from: JSONEncoder().encode(plan)) == plan)
        #expect(plan.notes.isEmpty)
    }

    @Test(arguments: [[0.5, 0.6], [1.5, -0.5], [Double.nan, 1], [0, 1]])
    func weightsMustBePositiveAndSumToOne(weights: [Double]) {
        #expect(throws: PlanError.badWeights) { try Self.plan(weights: weights) }
    }

    @Test func stagesLanesAndWeightsMustLineUp() {
        #expect(throws: PlanError.noStages) { try Self.plan(weights: []) }
        #expect(throws: PlanError.countMismatch) { try Self.plan(weights: [1], lanes: [.cpu, .cpu]) }
    }

    @Test func decodingRunsTheSameChecks() throws {
        let json = try String(decoding: JSONEncoder().encode(Self.plan(weights: [1])), as: UTF8.self)
        let broken = json.replacingOccurrences(of: "\"stageWeights\":[1]", with: "\"stageWeights\":[2]")
        #expect(broken != json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ExecutionPlan.self, from: Data(broken.utf8)) }
    }

    @Test(arguments: [(0, 0.5, 0.175), (1, 0.0, 0.35), (1, 1.0, 1.0)])
    func overallFractionWeighsEachStage(stage: Int, fraction: Double, expected: Double) throws {
        let plan = try Self.plan(weights: [0.35, 0.65])
        #expect(abs(plan.overallFraction(stage: stage, fraction: fraction) - expected) < 1e-9)
    }

    @Test func routeAvailabilityNamesWhatIsMissing() {
        #expect(RouteAvailability.available.isAvailable)
        #expect(!RouteAvailability.unavailable(["libvorbis"]).isAvailable)
    }
}

/// A fake clock and a recorder for the sink, both thread-safe.
final class SinkProbe: Sendable {
    let now = Mutex<Duration>(.zero)
    let delivered = Mutex<[Double?]>([])

    func sink(interval: Duration = .milliseconds(100)) -> ProgressSink {
        ProgressSink(clock: { self.now.withLock { $0 } }, interval: interval) { progress in
            self.delivered.withLock { $0.append(progress.fraction) }
        }
    }

    func advance(_ by: Duration) { now.withLock { $0 += by } }
    var values: [Double?] { delivered.withLock { $0 } }
}

@Suite("ProgressSink throttle (10 Hz) and monotonic fractions")
struct ProgressSinkTests {
    @Test func deliversAtMostTenTimesASecondButAlwaysTheFirstAndTheEnd() {
        let probe = SinkProbe()
        let sink = probe.sink()
        sink.report(0.1)
        probe.advance(.milliseconds(30))
        sink.report(0.2)
        probe.advance(.milliseconds(80))
        sink.report(0.3)
        sink.report(1.0)
        #expect(probe.values == [0.1, 0.3, 1.0])
    }

    @Test func fractionsNeverGoBackwards() {
        let probe = SinkProbe()
        let sink = probe.sink()
        sink.report(0.6)
        probe.advance(.seconds(1))
        sink.report(0.4)
        probe.advance(.seconds(1))
        sink.report(0.7)
        #expect(probe.values == [0.6, 0.7])
    }

    @Test func indeterminateIsReportedOnlyBeforeAnyFraction() {
        let probe = SinkProbe()
        let sink = probe.sink()
        sink.report(nil)
        probe.advance(.seconds(1))
        sink.report(0.5)
        probe.advance(.seconds(1))
        sink.report(nil)
        #expect(probe.values == [nil, 0.5])
    }

    @Test func discardSinkAcceptsReports() {
        ProgressSink.discard.report(0.5)
        #expect(ProgressSink.uptime() > .zero)
    }
}

@Suite("Image pipeline spec invariants")
struct ImagePipelineSpecTests {
    static func spec(frames: [Int] = [0], quality: Double? = 0.85) throws -> ImagePipelineSpec {
        try ImagePipelineSpec(
            source: URL(fileURLWithPath: "/in/a.png"), destinationType: "public.jpeg", output: .raster, frames: frames,
            flattenAlpha: true, quality: quality, tiffLZW: false, expectedSize: PixelSize(width: 4, height: 2))
    }

    @Test func aSpecRoundTripsInsideAPlan() throws {
        let plan = try ExecutionPlan(
            engine: .image, stages: [.image(Self.spec())], stageWeights: [1], lanes: [.cpu], outputFormat: .jpg,
            stagedFile: URL(fileURLWithPath: "/in/.zivlet-1.jpg"), notes: [.alphaFlattened])
        let decoded = try JSONDecoder().decode(ExecutionPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan)
        #expect(decoded.stages.first?.image?.expectedSize.description == "4×2")
        #expect(decoded.stages.first?.ffmpeg == nil)
    }

    @Test func framesAndQualityAreValidated() throws {
        #expect(throws: PlanError.noFrames) { try Self.spec(frames: []) }
        #expect(throws: PlanError.noFrames) { try Self.spec(frames: [-1]) }
        #expect(throws: PlanError.badQuality) { try Self.spec(quality: 1.5) }
        let json = String(decoding: try JSONEncoder().encode(Self.spec()), as: UTF8.self)
        let broken = json.replacingOccurrences(of: "\"frames\":[0]", with: "\"frames\":[]")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ImagePipelineSpec.self, from: Data(broken.utf8))
        }
    }
}

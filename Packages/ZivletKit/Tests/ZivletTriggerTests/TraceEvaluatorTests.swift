import DragTraceSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("Trace evaluator (P2-197)")
struct TraceEvaluatorTests {
    /// A fixed rule, so these counts do not move when the provisional constants are tuned.
    let rule = NotchProximity.Config(margin: 40, dwell: .milliseconds(100), maxSpeed: 800, release: 24)

    private func trace(_ label: DragTrace.Label, restingAt point: Point2D, ms: Int) throws -> DragTrace {
        let samples = stride(from: 0, through: ms, by: 8).map {
            DragTrace.Sample(t: Double($0), x: point.x, y: point.y, down: true)
        }
        return try DragTrace(label: label, display: try TraceDisplay.mbp14(), os: "test", samples: samples)
    }

    @Test func aHandMadeSetIsCountedExactly() throws {
        let housing = Point2D(x: 900, y: 1160)
        let elsewhere = Point2D(x: 300, y: 600)
        let traces = [
            try trace(.notch, restingAt: housing, ms: 200),
            try trace(.notch, restingAt: housing, ms: 200),
            try trace(.notch, restingAt: elsewhere, ms: 200),
            try trace(.normal, restingAt: elsewhere, ms: 200),
            try trace(.normal, restingAt: housing, ms: 200),
            try trace(.normal, restingAt: housing, ms: 40),
        ]
        let score = TraceEvaluator.score(traces, zones: TraceZones.provider(rule), config: rule)
        #expect(score == ProximityScore(notchBound: 3, detected: 2, normal: 3, accidental: 1))
        #expect(abs(score.detection - 2.0 / 3.0) < 1e-9)
        #expect(!score.meetsTheBar)
    }

    @Test func theBarNeeds95PercentAndNoAccidentalOpens() {
        #expect(ProximityScore(notchBound: 20, detected: 19, normal: 200, accidental: 0).meetsTheBar)
        #expect(!ProximityScore(notchBound: 20, detected: 18, normal: 200, accidental: 0).meetsTheBar)
        #expect(!ProximityScore(notchBound: 20, detected: 20, normal: 200, accidental: 1).meetsTheBar)
        #expect(!ProximityScore(notchBound: 0, detected: 0, normal: 200, accidental: 0).meetsTheBar)
    }

    @Test func eachTraceUsesItsOwnDisplaysZone() throws {
        let pill = try TraceDisplay.pill1080()
        let samples = stride(from: 0, through: 200, by: 8).map {
            DragTrace.Sample(t: Double($0), x: -960, y: 1070, down: true)
        }
        let onThePill = try DragTrace(label: .notch, display: pill, os: "test", samples: samples)
        let score = TraceEvaluator.score([onThePill], zones: TraceZones.provider(rule), config: rule)
        #expect(score.detected == 1)
    }
}

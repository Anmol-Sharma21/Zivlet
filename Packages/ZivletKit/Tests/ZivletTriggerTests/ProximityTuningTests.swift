import DragTraceSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("Proximity tuning grid (NB5, OS-M5b-1)")
struct ProximityTuningTests {
    private func trace(_ label: DragTrace.Label, restingAt point: Point2D, ms: Int) throws -> DragTrace {
        let samples = stride(from: 0, through: ms, by: 8).map {
            DragTrace.Sample(t: Double($0), x: point.x, y: point.y, down: true)
        }
        return try DragTrace(label: label, display: try TraceDisplay.mbp14(), os: "test", samples: samples)
    }

    /// Two notch drags resting 200 ms on the housing, one everyday drag resting 120 ms 30 pt beside it.
    private func handMade() throws -> [DragTrace] {
        [
            try trace(.notch, restingAt: Point2D(x: 900, y: 1160), ms: 200),
            try trace(.notch, restingAt: Point2D(x: 900, y: 1160), ms: 200),
            try trace(.normal, restingAt: Point2D(x: 1040, y: 1160), ms: 120),
        ]
    }

    @Test func rowsAreSortedByAccidentalOpensThenDetection() throws {
        let rows = ProximityTuning.grid(
            traces: try handMade(), margins: [0, 40], dwells: [.milliseconds(100), .milliseconds(150)],
            speeds: [800], zones: TraceZones.zones(for:margin:))
        #expect(rows.count == 4)
        #expect(rows.map(\.score.accidental) == [0, 0, 0, 1])
        #expect(rows.first?.config.margin == 0 && rows.first?.score.detection == 1)
        #expect(
            rows.last?.config
                == NotchProximity.Config(margin: 40, dwell: .milliseconds(100), maxSpeed: 800, release: 24))
    }

    @Test func theStandardGridHasEveryCombination() {
        let grid = ProximityTuning.standard
        #expect(grid.margins == [0, 20, 40, 60, 80])
        #expect(grid.dwells == [0, 50, 100, 150, 200].map { .milliseconds($0) })
        #expect(grid.speeds == [400, 800, 1600, nil])
    }

    @Test func aRowReadsAsOneLine() {
        let row = ProximityTuning.Row(
            config: NotchProximity.Config(margin: 30, dwell: .milliseconds(240), maxSpeed: nil, release: 24),
            score: ProximityScore(notchBound: 50, detected: 49, normal: 200, accidental: 0))
        #expect(row.line == "margin 30 pt  dwell 240 ms  speed none  detection 98.0 % (49/50)  accidental 0/200")
    }
}

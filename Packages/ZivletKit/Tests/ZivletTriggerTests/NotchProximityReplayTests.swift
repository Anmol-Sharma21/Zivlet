import DragTraceSupport
import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

/// NB5's replay (P2-197). The synthetic sets check the provisional rule on made-up drags only; the P2-197 bar is
/// judged on the owner's recordings (`make drag-replay TRACES=<folder>`, OS-M5b-1) and is not claimed here.
@Suite("Notch proximity replay (P2-197, NB5)")
struct NotchProximityReplayTests {
    static let seeds: [UInt64] = [1, 2, 3, 4, 5]

    @Test(arguments: seeds)
    func syntheticDragsOnTheRecorded14InchDisplay(seed: UInt64) throws {
        try expectTheBar(on: try TraceDisplay.mbp14(), seed: seed)
    }

    @Test(arguments: seeds)
    func syntheticDragsOnAPillDisplay(seed: UInt64) throws {
        try expectTheBar(on: try TraceDisplay.pill1080(), seed: seed)
    }

    @Test(
        .enabled(
            if: RecordedDrags.folder != nil,
            "No recordings: run make drag-replay TRACES=<folder> with the owner's recorded drags (OS-M5b-1)"))
    func recordedDragsMeetTheBar() throws {
        let folder = try #require(RecordedDrags.folder)
        let verdict = try RecordedVerdict.judge(folder: folder)
        ReplayReport.write("recorded", verdict.score)
        #expect(verdict.problems.isEmpty, "\(verdict.problems.joined(separator: "; "))")
    }

    @Test func aFolderWithAnInvalidTraceFails() throws {
        let dir = try TempDir()
        try write(try enoughTraces(), to: dir.url)
        try Data(#"{"schema":1}"#.utf8).write(to: dir.url.appending(path: "zz-broken.json"))
        let verdict = try RecordedVerdict.judge(folder: dir.url)
        #expect(verdict.problems.contains { $0.hasPrefix("zz-broken.json:") })
    }

    @Test func aFolderWithTooFewTracesFails() throws {
        let dir = try TempDir()
        let few = try SyntheticDrags.proximitySet(on: try TraceDisplay.mbp14(), seed: 9, normal: 20, notchBound: 5)
        try write(few, to: dir.url)
        let verdict = try RecordedVerdict.judge(folder: dir.url)
        #expect(verdict.problems.contains("5 notch traces; the bar needs at least 50"))
        #expect(verdict.problems.contains("20 normal traces; the bar needs at least 200"))
    }

    @Test func theReportLineCarriesBothNumbers() {
        let score = ProximityScore(notchBound: 50, detected: 49, normal: 200, accidental: 0)
        #expect(ReplayReport.line("x", score) == "proximity x: detection 98.0 % (49/50), accidental opens 0/200\n")
    }

    @Test func aFullGoodFolderPasses() throws {
        let dir = try TempDir()
        try write(try enoughTraces(), to: dir.url)
        #expect(try RecordedVerdict.judge(folder: dir.url).problems.isEmpty)
    }

    // MARK: - Helpers

    private func expectTheBar(on display: TraceDisplay, seed: UInt64) throws {
        let config = NotchProximity.Config.provisional
        let traces = try SyntheticDrags.proximitySet(on: display, seed: seed)
        let score = TraceEvaluator.score(traces, zones: TraceZones.provider(config), config: config)
        ReplayReport.write("synthetic display \(display.id) seed \(seed)", score)
        #expect(score.notchBound == 50 && score.normal == 200)
        #expect(score.detection >= 0.95, "detection \(score.detection) on display \(display.id), seed \(seed)")
        #expect(score.accidental == 0, "\(score.accidental) accidental opens on display \(display.id), seed \(seed)")
    }

    private func enoughTraces() throws -> [DragTrace] {
        try SyntheticDrags.proximitySet(on: try TraceDisplay.mbp14(), seed: 1)
    }

    private func write(_ traces: [DragTrace], to folder: URL) throws {
        for (index, trace) in traces.enumerated() {
            let name = "\(trace.label.rawValue)-\(String(index + 1000)).json"
            try JSONEncoder().encode(trace).write(to: folder.appending(path: name))
        }
    }
}

/// One line per replayed set on standard error, so the Y7 log carries the numbers and not only a pass (G-M5b-6):
/// "proximity <set>: detection 98.0 % (49/50), accidental opens 0/200".
enum ReplayReport {
    static func line(_ name: String, _ score: ProximityScore) -> String {
        let percent = String(format: "%.1f", score.detection * 100)
        return "proximity \(name): detection \(percent) % (\(score.detected)/\(score.notchBound)), "
            + "accidental opens \(score.accidental)/\(score.normal)\n"
    }

    static func write(_ name: String, _ score: ProximityScore) {
        FileHandle.standardError.write(Data(line(name, score).utf8))
    }
}

/// The P2-197 bar on a folder of recordings: every file valid, at least 50 notch and 200 normal traces, detection
/// of at least 95 % and no accidental open, each trace replayed against its own display's zone.
enum RecordedVerdict {
    static let minimumNotch = 50
    static let minimumNormal = 200

    static func judge(folder: URL, config: NotchProximity.Config = .provisional) throws -> (
        score: ProximityScore, problems: [String]
    ) {
        let loaded = try DragTraceFolder.load(from: folder)
        let score = TraceEvaluator.score(loaded.traces.map(\.trace), zones: TraceZones.provider(config), config: config)
        var problems = loaded.invalid.map { "\($0.name): \($0.reason)" }
        if score.notchBound < minimumNotch {
            problems.append("\(score.notchBound) notch traces; the bar needs at least \(minimumNotch)")
        }
        if score.normal < minimumNormal {
            problems.append("\(score.normal) normal traces; the bar needs at least \(minimumNormal)")
        }
        if score.detection < 0.95 { problems.append("detection \(score.detection); the bar is 0.95") }
        if score.accidental > 0 { problems.append("\(score.accidental) accidental opens; the bar is 0") }
        return (score, problems)
    }
}

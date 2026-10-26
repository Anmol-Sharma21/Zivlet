import DragTraceSupport
import Foundation
import TestSupport
import Testing
import ZivletTrigger

@testable import zivlet_traces

@Suite("zivlet-traces (NB5 dev tool)")
struct TracesToolTests {
    private func run(_ arguments: [String]) -> (status: Int32, text: String) {
        var text = ""
        let status = TracesTool.run(arguments: arguments) { text += $0 }
        return (status, text)
    }

    private func folderWithTwoTraces() throws -> TempDir {
        let dir = try TempDir()
        let traces = try SyntheticDrags.proximitySet(on: try TraceDisplay.mbp14(), seed: 4, normal: 0, notchBound: 2)
        for (index, trace) in traces.enumerated() {
            try JSONEncoder().encode(trace).write(to: dir.url.appending(path: "notch-\(index).json"))
        }
        return dir
    }

    @Test func reportScoresTheProvisionalRule() throws {
        let dir = try folderWithTwoTraces()
        let (status, text) = run(["report", dir.url.path])
        #expect(status == 0)
        #expect(text.contains("2 traces (2 notch, 0 normal)"))
        #expect(text.contains("provisional: margin 30 pt"))
    }

    @Test func tuneListsTheGridBestFirst() throws {
        let dir = try folderWithTwoTraces()
        let (status, text) = run(["tune", dir.url.path])
        #expect(status == 0)
        #expect(text.split(separator: "\n").filter { $0.hasPrefix("margin ") }.count == 100)
    }

    @Test func invalidFilesAreListedWithTheirReasons() throws {
        let dir = try folderWithTwoTraces()
        try Data(#"{"schema":3}"#.utf8).write(to: dir.url.appending(path: "old.json"))
        let (status, text) = run(["report", dir.url.path])
        #expect(status == 0)
        #expect(text.contains("left out old.json: Trace schema 3 is not supported"))
    }

    @Test func aWrongCommandPrintsUsageAndFails() {
        #expect(run([]).status == 64)
        #expect(run(["dance", "/tmp"]).text.contains("usage: zivlet-traces report|tune <folder>"))
    }

    @Test func aMissingFolderFailsWithAPlainMessage() {
        let (status, text) = run(["report", "/nonexistent-zivlet-traces-folder"])
        #expect(status == 1)
        #expect(text.contains("cannot read the folder"))
    }
}

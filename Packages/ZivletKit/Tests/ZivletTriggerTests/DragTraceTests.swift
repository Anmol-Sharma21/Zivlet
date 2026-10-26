import DragTraceSupport
import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

/// Trace files with one rule broken each (the samples start at x 900, y 500 on the 14-inch display).
enum DragTraceFixtures {
    static let display = """
        {"id":1,"frame":{"x":0,"y":0,"width":1800,"height":1169},\
        "visibleFrame":{"x":0,"y":94,"width":1800,"height":1036},"safeAreaTop":38}
        """

    static func json(
        schema: Int = 1, label: String = "notch", display: String = display, samples: String = twoSamples,
        truncated: Bool = false
    ) -> String {
        """
        {"schema":\(schema),"label":"\(label)","display":\(display),"os":"27.0","samples":\(samples),\
        "truncated":\(truncated)}
        """
    }

    static let twoSamples = #"[{"t":0,"x":900,"y":500,"down":true},{"t":8,"x":901,"y":500,"down":true}]"#

    static let valid = json()

    static let invalid: [String] = [
        json(schema: 2),
        json(label: "maybe"),
        json(samples: #"[{"t":0,"x":900,"y":500,"down":true}]"#),
        json(samples: #"[{"t":0,"x":900,"y":500,"down":true},{"t":-1,"x":900,"y":500,"down":true}]"#),
        json(samples: #"[{"t":0,"x":900,"y":500,"down":true},{"t":8,"x":1901,"y":500,"down":true}]"#),
        json(samples: #"[{"t":0,"x":900,"y":500,"down":true},{"t":8,"x":900,"y":-101,"down":true}]"#),
        json(
            display: display.replacingOccurrences(of: #""width":1800,"height":1169"#, with: #""width":0,"height":1169"#)
        ),
        json(truncated: true),
    ]
}

@Suite("Drag traces (P2-197 recordings)")
struct DragTraceTests {
    @Test func aValidTraceDecodes() throws {
        let trace = try JSONDecoder().decode(DragTrace.self, from: Data(DragTraceFixtures.valid.utf8))
        #expect(trace.label == .notch && trace.samples.count == 2 && trace.os == "27.0" && !trace.truncated)
        #expect(trace.inputSamples.map(\.uptime) == [.zero, .milliseconds(8)])
    }

    @Test(arguments: DragTraceFixtures.invalid)
    func invalidTracesAreRefused(_ json: String) {
        #expect(throws: DragTraceError.self) { try JSONDecoder().decode(DragTrace.self, from: Data(json.utf8)) }
    }

    @Test func tooManySamplesAreRefused() throws {
        let display = try TraceDisplay.mbp14()
        let samples = (0...DragTrace.sampleLimits.upperBound).map {
            DragTrace.Sample(t: Double($0), x: 900, y: 500, down: true)
        }
        #expect(throws: DragTraceError.sampleCount(20_001)) {
            try DragTrace(label: .normal, display: display, os: "27.0", samples: samples)
        }
    }

    @Test func aNumberThatIsNotFiniteIsRefused() throws {
        let samples = [
            DragTrace.Sample(t: 0, x: 900, y: 500, down: true), DragTrace.Sample(t: 8, x: .nan, y: 500, down: true),
        ]
        #expect(throws: DragTraceError.notFinite(sample: 1)) {
            try DragTrace(label: .normal, display: try TraceDisplay.mbp14(), os: "27.0", samples: samples)
        }
    }

    @Test func aPointerPinnedToTheTopEdgeIsOnTheDisplay() throws {
        let samples = [
            DragTrace.Sample(t: 0, x: 900, y: 1169, down: true), DragTrace.Sample(t: 8, x: 900, y: 1169, down: true),
        ]
        #expect(throws: Never.self) {
            try DragTrace(label: .notch, display: try TraceDisplay.mbp14(), os: "27.0", samples: samples)
        }
    }

    @Test func samplesWithTheButtonUpAreLeftOutOfTheReplay() throws {
        let samples = [
            DragTrace.Sample(t: 0, x: 900, y: 500, down: true), DragTrace.Sample(t: 8, x: 900, y: 500, down: false),
        ]
        let trace = try DragTrace(label: .normal, display: try TraceDisplay.mbp14(), os: "27.0", samples: samples)
        #expect(trace.inputSamples.count == 1)
    }

    @Test func everyRefusalSaysWhyInZivletsWords() {
        let errors: [DragTraceError] = [
            .unsupportedSchema(2), .unknownLabel("x"), .sampleCount(1), .notFinite(sample: 3), .timeGoesBack(sample: 4),
            .outsideDisplay(sample: 5), .badDisplay, .truncated,
        ]
        #expect(Set(errors.map(\.description)).count == errors.count)
        #expect(errors.allSatisfy { !$0.description.contains("/") })
    }

    @Test func aFolderListsBadFilesWithTheirReasonsAndKeepsTheRest() throws {
        let dir = try TempDir()
        try Data(DragTraceFixtures.valid.utf8).write(to: dir.url.appending(path: "a-good.json"))
        try Data(DragTraceFixtures.json(schema: 2).utf8).write(to: dir.url.appending(path: "b-schema.json"))
        try Data("{".utf8).write(to: dir.url.appending(path: "c-broken.json"))
        try Data("ignored".utf8).write(to: dir.url.appending(path: "notes.txt"))
        let loaded = try DragTraceFolder.load(from: dir.url)
        #expect(loaded.traces.map(\.name) == ["a-good.json"])
        #expect(loaded.invalid.map(\.name) == ["b-schema.json", "c-broken.json"])
        #expect(loaded.invalid.first?.reason == DragTraceError.unsupportedSchema(2).description)
    }
}

import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("Trigger trace for diagnostics (P1-48)")
struct TriggerTraceTests {
    /// Folds events through the machine, recording the trace the way the host does.
    static func traced(_ events: [TriggerEvent], start: TriggerTrace = TriggerTrace()) -> TriggerTrace {
        var machine = TriggerMachine()
        var trace = start
        for event in events {
            let step = machine.step(event)
            if let entry = TriggerTrace.entry(event: event, from: machine.state, step: step) {
                trace = trace.recording(entry)
            }
            machine = step.next
        }
        return trace
    }

    @Test func aFileDragAndATapAreTracedStateByState() {
        let trace = Self.traced(T.fileDrag() + T.tap(.shift, at: 70))
        #expect(trace.entries.map(\.to) == ["pressed", "detecting", "live", "wheel"])
        #expect(trace.entries.last?.effects == ["show"])
        #expect(trace.lines.last == "+0.070 s  sample.flagsChanged  live → wheel  [show]")
    }

    @Test func samplesThatChangeNothingAreNotRecorded() {
        let trace = Self.traced(T.fileDrag() + [T.sample(30), T.sample(40), T.sample(50)])
        #expect(trace.entries.count == 3)
    }

    @Test func onlyTheLastFiftyEntriesAreKept() {
        let entry = TriggerTrace.Entry(uptime: .zero, event: "escape", from: "wheel", to: "idle", effects: [])
        let trace = (0..<70).reduce(TriggerTrace()) { trace, _ in trace.recording(entry) }
        #expect(trace.entries.count == TriggerTrace.capacity && TriggerTrace.capacity == 50)
    }

    @Test func linesNameNoFilesOrPaths() {
        let trace = Self.traced(T.fileDrag() + T.tap(.shift, at: 70) + [.escape])
        #expect(trace.lines.allSatisfy { !$0.contains("/") })
        #expect(trace.entries.last?.event == "escape")
    }
}

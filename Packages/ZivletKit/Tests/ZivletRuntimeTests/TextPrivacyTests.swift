import EngineVision
import Foundation
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore

@testable import ZivletRuntime

/// D14 (P2-104): recognised text is copied and shown, never logged or stored. A job reads a unique marker sentence,
/// then the process's own log (what Copy Diagnostics reads), the diagnostics report and the undo store are searched
/// for it.
@Suite("Recognised text is never logged or stored (plan 18d D14)")
struct TextPrivacyTests {
    @Test func theMarkerIsInTheResultAndNowhereElse() async throws {
        let marker = "Zivlet privacy marker \(UUID().uuidString)"
        let rig = try TextRig(texts: [marker])
        let started = Date()
        let undoFile = rig.dir.url.appending(path: "undo.json")
        let history = UndoHistory(store: UndoStore(file: undoFile))
        let text = try await rig.service.copyText([try rig.png("note.png")], languages: [.english])
        #expect(text.text.contains(marker))

        let log = DiagnosticsCollector.recentLog(limit: 10_000, since: started.addingTimeInterval(-1))
        #expect(!log.joined(separator: "\n").contains(marker))
        let sources = await DiagnosticsCollector(tools: nil).collect(
            settingsJSON: "{}", triggerTrace: [], helpers: [])
        let report = try await Diagnostics.build(sources)
        #expect(!report.contains(marker))
        #expect(await history.recent().isEmpty)
        let stored = (try? String(contentsOf: undoFile, encoding: .utf8)) ?? ""
        #expect(!stored.contains(marker))
    }
}

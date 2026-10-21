import Darwin
import Foundation
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

@Suite("Diagnostics report (P1-48)")
struct DiagnosticsTests {
    @Test func noUnredactedHomePathSurvives() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let report = DiagnosticsRedaction.redact(
            """
            opened \(home)/Desktop/secret plan.mov
            wrote /Volumes/Card/DCIM/IMG_0001.HEIC
            """, home: home)
        #expect(!report.contains(home) && !report.contains("Desktop") && !report.contains("DCIM"))
        #expect(report.contains("…/secret plan.mov") && report.contains("…/IMG_0001.HEIC"))
    }

    @Test(arguments: [
        ("folder ~/Movies/Holiday/clip.mov", "folder ~/…/clip.mov"),
        ("url file:///Users/x/a/b.png done", "url file:…/b.png done"),
        ("\"/private/var/folders/xy/T/a.txt\"", "\"…/a.txt\""),
        ("no paths here", "no paths here"),
        ("ratio 3/4 and 1/2", "ratio 3/4 and 1/2"),
    ])
    func pathsKeepOnlyTheirLastComponent(line: String, redacted: String) {
        #expect(DiagnosticsRedaction.redact(line, home: "/Users/x") == redacted)
    }

    @Test func homePathsAreMarkedAsHome() {
        #expect(DiagnosticsRedaction.redact("in /Users/x/Downloads", home: "/Users/x") == "in ~/…/Downloads")
    }

    @Test func reportHasEverySectionAndNoNetworkFields() async throws {
        let report = try await Diagnostics.build(.fake)
        for section in ["Zivlet", "macOS", "Helpers", "Capabilities", "Settings", "Recent log", "Trigger trace"] {
            #expect(report.contains("## \(section)"))
        }
        #expect(!report.contains("http"))
    }

    @Test func theReportCarriesTheSourcesButNoFolderNames() async throws {
        let report = try await Diagnostics.build(.fake)
        #expect(report.contains("0.1.0 (42)") && report.contains("ffmpeg 9.0.2") && report.contains("abc123"))
        #expect(report.contains("live → wheel") && report.contains("Job finished"))
        #expect(!report.contains("Projects") && report.contains("~/…/Downloads"))
    }

    @Test func recentLogKeepsOnlyTheLastTwoHundredLines() async throws {
        let lines = (1...250).map { "line \($0)" }
        let report = try await Diagnostics.build(DiagnosticsSources.fake.with(log: lines))
        #expect(!report.contains("line 50\n") && report.contains("line 51\n") && report.contains("line 250"))
    }

    @Test func helperHashesAreSHA256OfTheFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "zivlet-hash-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(
            DiagnosticsCollector.sha256(of: file)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(DiagnosticsCollector.sha256(of: file.appending(path: "missing")) == nil)
    }

    /// The log store is read from ten minutes back, not from the start of the process (a long session has a lot).
    @Test func theLogIsReadFromTenMinutesBack() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(DiagnosticsCollector.logStart(now: now) == Date(timeIntervalSince1970: 9_400))
    }

    /// Called from the main actor (the Settings button), the hashing and the log read still run off it.
    @Test @MainActor func collectingRunsOffTheMainThread() async {
        let onMain = Mutex<[Bool]>([])
        let collector = DiagnosticsCollector(observe: { onMain.withLock { $0.append(pthread_main_np() != 0) } })
        _ = await collector.collect(settingsJSON: "{}", triggerTrace: [], helpers: [])
        #expect(onMain.withLock { $0 } == [false])
    }

    @Test func theLiveCollectorFillsEverySectionWithoutNetwork() async throws {
        let sources = await DiagnosticsCollector().collect(
            settingsJSON: "{\"version\":1}", triggerTrace: ["+0.000 s  escape  wheel → idle  []"], helpers: [])
        #expect(!sources.macOS.isEmpty && !sources.model.isEmpty && sources.settings == "{\"version\":1}")
        let report = try await Diagnostics.build(sources)
        #expect(report.contains("## Recent log") && report.contains("wheel → idle"))
    }
}

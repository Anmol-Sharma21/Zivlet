import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletRuntime
import os

@testable import ZivletIPC

/// P2-102's policy (plan 20c B7, D-M7-14): a password leaves no trace in the log, the diagnostics, file names or
/// contents, or the command line and environment of a child. Each probe is first shown to catch a planted leak. The
/// password is random per run, so a match cannot be a coincidence. Lock, Unlock and Change through the worker join
/// these tests with stream E (E4–E7); today they cover the password's type, its wire form and the log.
@Suite("A password leaves no trace")
struct PasswordPolicyTests {
    private let password = "zv-test-" + UUID().uuidString
    private var needle: [UInt8] { Array(password.utf8) }
    private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

    private struct Holder {
        let job: String
        let secrets: JobSecrets
    }

    // MARK: The probes catch planted leaks

    @Test func theLogProbeCatchesAPasswordLoggedInPublic() throws {
        let start = Date()
        Self.logger.error("planted leak: \(password, privacy: .public)")
        #expect(LeakProbe.contains(needle, in: try LeakProbe.logLines(since: start)))
    }

    @Test func theDefaultsProbeCatchesAPasswordInASuite() throws {
        let suite = "zivlet-policy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!LeakProbe.contains(needle, in: try LeakProbe.bytes(of: defaults)))
        defaults.set(Data(needle), forKey: "planted")
        #expect(LeakProbe.contains(needle, in: try LeakProbe.bytes(of: defaults)))
    }

    @Test func theFolderProbeCatchesAPasswordInANameOrAFile() throws {
        let folder = try TempDir()
        try folder.file("clean.txt", "nothing here")
        #expect(LeakProbe.leaks(needle, under: folder.url).isEmpty)
        try folder.file("inner/\(password).pdf", "x")
        try folder.file("inner/note.txt", "the password was \(password)")
        #expect(LeakProbe.leaks(needle, under: folder.url).count == 2)
    }

    @Test func theChildProbeCatchesAPasswordOnARunningChildsCommandLine() async throws {
        let token = "zv-probe-" + UUID().uuidString
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "read line", "probe", "--password=\(token)"]
        let input = Pipe()
        child.standardInput = input
        try child.run()
        defer {
            try? input.fileHandleForWriting.close()
            child.waitUntilExit()
        }
        var seen = Data()
        for _ in 0..<200 where !LeakProbe.contains(Array(token.utf8), in: seen) {
            seen = LeakProbe.commandLine(of: child.processIdentifier) ?? Data()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(LeakProbe.contains(Array(token.utf8), in: seen))
        #expect(!LeakProbe.contains(needle, in: seen))
    }

    @Test func theSpawnProbeCatchesAPasswordInArgumentsOrEnvironment() {
        #expect(LeakProbe.contains(needle, arguments: ["--password=\(password)"], environment: [:]))
        #expect(LeakProbe.contains(needle, arguments: [], environment: ["ZV_PASSWORD": password]))
        #expect(!LeakProbe.contains(needle, arguments: ["-i", "in.pdf"], environment: ["LANG": "C"]))
    }

    @Test func theTextProbeFindsBytesAnywhereInAText() {
        #expect(LeakProbe.contains(needle, in: ["one", "two \(password) three"]))
        #expect(!LeakProbe.contains(needle, in: ["one", "two"]))
        #expect(!LeakProbe.contains([], in: ["anything"]))
    }

    // MARK: The policy

    @Test func aSecretLoggedThroughEveryDescriptionLeavesNoTrace() throws {
        let start = Date()
        let secret = JobSecret(utf8: password)
        let holder = Holder(job: "unlock", secrets: JobSecrets(input: secret, owner: secret))
        let wire = WireSecret(secret)
        Self.logger.error("policy: \(String(describing: secret), privacy: .public)")
        Self.logger.error("policy: \(String(reflecting: holder), privacy: .public)")
        Self.logger.error("policy: \(String(describing: wire), privacy: .public)")
        var dumped = ""
        dump(holder, to: &dumped)
        Self.logger.error("policy: \(dumped, privacy: .public)")
        let lines = try LeakProbe.logLines(since: start)
        #expect(lines.contains { $0.contains(JobSecret.redacted) })
        #expect(!LeakProbe.contains(needle, in: lines))
    }

    @Test func theDiagnosticsFromTheLiveLogCarryNoPassword() async throws {
        let start = Date()
        let secret = JobSecret(utf8: password)
        Self.logger.notice("policy: diagnostics with \(String(describing: secret), privacy: .public)")
        // Other suites log in the same process meanwhile; the report keeps the last 200 lines, so this test's line
        // goes in by itself, and the whole log is searched as well.
        let all = try LeakProbe.logLines(since: start)
        let lines = all.filter { $0.contains("policy: diagnostics") }
        let text = try await Diagnostics.build(DiagnosticsSources.fake.with(log: lines))
        #expect(!LeakProbe.contains(needle, in: all))
        #expect(text.contains(JobSecret.redacted))
        #expect(!LeakProbe.contains(needle, in: [text]))
    }

    /// The one place the bytes may go: the worker request of their job. The wire form carries them as data, and the
    /// secret rebuilt on the other side is the same.
    @Test func theWireCarriesTheBytesOnlyAsData() throws {
        let data = try JSONEncoder().encode(WireSecret(JobSecret(utf8: password)))
        #expect(!LeakProbe.contains(needle, in: data))
        let back = try JSONDecoder().decode(WireSecret.self, from: data).secret()
        #expect(back.withBytes { Array($0) } == needle)
    }
}

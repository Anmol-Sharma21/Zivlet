import EnginePDF
import EngineTestSupport
import Foundation
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletRuntime

@testable import ZivletWorkerCore

/// P2-102 through real LOCK · UNLOCK jobs in the loopback worker (plan 20c B7, deferred to stream E, G-M7-17): after
/// a lock, an unlock, a change, a wrong attempt and a cancelled job, the password is in no log line, no file name or
/// file content in the folder (staging and job records included), no undo log, and the secrets read zero.
@Suite("No password left behind by real protect jobs")
struct ProtectPolicyTests {
    @Test func lockUnlockChangeWrongAndCancelLeaveNoTrace() async throws {
        let start = Date()
        let rig = try await ProtectWorkerRig()
        let (first, second) = ("zv-policy-" + UUID().uuidString, "zv-policy-" + UUID().uuidString)
        let wrong = "zv-policy-" + UUID().uuidString
        let source = try PDFFixtures.plain(in: rig.dir.url, name: "Policy.pdf")
        var given: [JobSecret] = []
        func secret(_ text: String) -> JobSecret {
            let made = JobSecret(utf8: text)
            given.append(made)
            return made
        }

        let locked = await rig.run([try rig.request(source, .lock(nil))], JobSecrets(newUser: secret(first)))
        let lockedURL = try #require(locked.first?.publishedURL)
        let change = JobSecrets(input: secret(first), newUser: secret(second))
        let changed = await rig.run([try rig.request(lockedURL, .changePassword)], change)
        let changedURL = try #require(changed.first?.publishedURL)
        let unlock = try rig.request(changedURL, .unlock)
        let refused = await rig.run([unlock], JobSecrets(input: secret(wrong)))
        #expect(refused == [.failed(.wrongPassword)])
        let unlocked = await rig.run([try rig.request(changedURL, .unlock)], JobSecrets(input: secret(second)))
        #expect(unlocked.first?.publishedURL != nil)
        try await cancelledLock(rig, source: source, secret: secret("zv-policy-" + UUID().uuidString))

        let history = UndoHistory(store: UndoStore(file: rig.dir.url.appending(path: "undo.json")))
        await history.record(BatchID(), outputs: locked.compactMap(\.published))

        let lines = try LeakProbe.logLines(since: start)
        for password in [first, second, wrong] {
            let needle = Array(password.utf8)
            #expect(!LeakProbe.contains(needle, in: lines), "log")
            #expect(LeakProbe.leaks(needle, under: rig.dir.url).isEmpty, "files")
        }
        #expect(given.allSatisfy { $0.isWiped })
    }

    /// A lock cancelled while it runs: its staging goes and its secret is wiped.
    private func cancelledLock(_ rig: ProtectWorkerRig, source: URL, secret: JobSecret) async throws {
        let request = try rig.request(source, .lock(nil))
        let batch = await rig.scheduler.submit(
            [request], secrets: BatchSecrets.shared(JobSecrets(newUser: secret), for: [request.id]))
        await rig.scheduler.cancel(batch: batch)
        await rig.scheduler.waitUntilIdle()
        let staging = try FileManager.default.contentsOfDirectory(atPath: rig.dir.url.path)
            .filter { $0.hasPrefix(JobWorkspace.stagingFolderPrefix) }
        #expect(staging.isEmpty)
    }
}

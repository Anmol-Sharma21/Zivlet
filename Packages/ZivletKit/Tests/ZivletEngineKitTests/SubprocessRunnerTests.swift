import Darwin
import Foundation
import Synchronization
import Testing
import ZivletCore

@testable import ZivletEngineKit

/// Integration tests against `/bin/sh` (P1-20): status, signals, caps, environment, process-group teardown.
@Suite("SubprocessRunner (P1-20, 10 §8.3)")
struct SubprocessRunnerTests {
    static let sh = URL(fileURLWithPath: "/bin/sh")
    let runner = SubprocessRunner()

    func shell(_ script: String, stdoutLimit: Int = 1 << 20, tail: Int = 64 << 10) -> SubprocessRequest {
        SubprocessRequest(
            executable: Self.sh, arguments: ["-c", script], stdoutLimit: stdoutLimit, stderrTailLimit: tail)
    }

    @Test func reportsTheExitStatusStdoutAndStderr() async throws {
        let result = try await runner.run(shell("echo hello; echo oops >&2; exit 3"))
        #expect(result.termination == .exited(3))
        #expect(String(decoding: result.stdout, as: UTF8.self) == "hello\n")
        #expect(result.stderrTail == "oops\n")
        #expect(!result.stdoutTruncated)
    }

    @Test func aKilledChildReportsTheSignal() async throws {
        let result = try await runner.run(shell("kill -9 $$"))
        #expect(result.termination == .signaled(SIGKILL))
    }

    @Test func stdoutIsCappedAndFlaggedAsTruncated() async throws {
        let result = try await runner.run(shell("head -c 100000 /dev/zero", stdoutLimit: 1_000))
        #expect(result.stdout.count == 1_000)
        #expect(result.stdoutTruncated)
    }

    @Test func stderrKeepsOnlyTheTail() async throws {
        let result = try await runner.run(shell("head -c 200000 /dev/zero | tr '\\0' a >&2; echo END >&2", tail: 100))
        #expect(result.stderrTail.utf8.count == 100)
        #expect(result.stderrTail.hasSuffix("aaaEND\n"))
    }

    @Test func stdoutLinesAreStreamedInOrder() async throws {
        let lines = Mutex<[String]>([])
        _ = try await runner.run(shell("printf 'a\\nb\\nc'"), onLine: { line in lines.withLock { $0.append(line) } })
        #expect(lines.withLock { $0 } == ["a", "b", "c"])
    }

    @Test func theChildGetsOnlyTheFixedEnvironment() async throws {
        let request = SubprocessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [],
            environment: ChildEnvironment.fixed(temporaryDirectory: "/private/tmp/zivlet-test"))
        let output = String(decoding: try await runner.run(request).stdout, as: UTF8.self)
        let keys = Set(output.split(separator: "\n").compactMap { $0.split(separator: "=").first.map(String.init) })
        #expect(keys == ["PATH", "LC_ALL", "TMPDIR", "AV_LOG_FORCE_NOCOLOR", "SVT_LOG"])
        #expect(output.contains("PATH=/usr/bin:/bin\n"))
    }

    /// A child reaped by someone else has an unknown outcome; it must never read as "exited 0".
    @Test func aChildReapedElsewhereIsAWaitFailureNotASuccess() async {
        await #expect(throws: SubprocessError.waitFailed(errno: ECHILD)) {
            try await runner.run(
                shell("exit 0"),
                onSpawn: { pid in
                    var status: Int32 = 0
                    while waitpid(pid, &status, 0) == -1, errno == EINTR {}
                })
        }
    }

    /// Only a helper that is not there or cannot be executed is "missing"; EMFILE and friends keep their errno.
    @Test(arguments: [
        (SubprocessError.launchFailed(errno: ENOENT), JobError.engineMissing(.media)),
        (.launchFailed(errno: EACCES), .engineMissing(.media)),
        (.launchFailed(errno: ENOEXEC), .engineMissing(.media)),
        (.launchFailed(errno: EMFILE), .helperFailed(errno: EMFILE)),
        (.launchFailed(errno: EAGAIN), .helperFailed(errno: EAGAIN)),
        (.waitFailed(errno: ECHILD), .helperFailed(errno: ECHILD)),
        (.cancelled, .cancelled),
    ])
    func runnerErrorsMapToAccurateJobErrors(error: SubprocessError, expected: JobError) {
        #expect(error.jobError(engine: .media) == expected)
    }

    @Test func aMissingExecutableIsALaunchFailure() async {
        let request = SubprocessRequest(executable: URL(fileURLWithPath: "/nonexistent/tool"), arguments: [])
        await #expect(throws: SubprocessError.launchFailed(errno: ENOENT)) { try await runner.run(request) }
    }

    @Test func theChildLeadsItsOwnProcessGroup() async throws {
        let spawned = Mutex<Int32>(0)
        let result = try await runner.run(
            shell("echo $$; /bin/ps -o pgid= -p $$"),
            onSpawn: { pid in
                spawned.withLock { $0 = pid }
            })
        let fields = String(decoding: result.stdout, as: UTF8.self).split(whereSeparator: \.isWhitespace)
        let pid = spawned.withLock { $0 }
        #expect(pid > 0)
        #expect(fields.map(String.init) == ["\(pid)", "\(pid)"])
    }

    @Test func cancellingKillsTheWholeGroupWithinOneSecond() async throws {
        let spawned = Mutex<Int32>(0)
        let task = Task {
            try await runner.run(shell("sleep 100 & sleep 100"), onSpawn: { pid in spawned.withLock { $0 = pid } })
        }
        try await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: SubprocessError.cancelled) { try await task.value }
        #expect(ContinuousClock.now - start < .milliseconds(1_500))
        #expect(await Self.groupIsGone(spawned.withLock { $0 }))
    }

    /// A SIGKILLed background member stays a zombie until launchd reaps it, and signalling a group of zombies fails
    /// with EPERM rather than ESRCH, so the group counts as gone once ESRCH arrives within `limit`.
    static func groupIsGone(_ group: Int32, within limit: Duration = .milliseconds(500)) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            let result = killpg(group, 0)
            let code = errno
            if result == -1, code == ESRCH { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test func aChildIgnoringSIGINTIsKilledAfterTheGrace() async throws {
        let task = Task { try await runner.run(shell("trap '' INT; sleep 100")) }
        try await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: SubprocessError.cancelled) { try await task.value }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed >= .milliseconds(900) && elapsed < .milliseconds(2_000))
    }

    /// Each child blocks threads while it runs (pipe reads, the exit wait). With many children at once, those must not
    /// exhaust the shared dispatch pool, or a cancelled child's SIGKILL and reap wait for unrelated children to end.
    @Test func teardownIsPromptWhileManyOtherChildrenRun() async throws {
        let sleepers = (0..<80).map { _ in Task { try await runner.run(shell("sleep 3")) } }
        try await Task.sleep(for: .milliseconds(300))
        let task = Task { try await runner.run(shell("trap '' INT; sleep 100")) }
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: SubprocessError.cancelled) { try await task.value }
        #expect(ContinuousClock.now - start < .milliseconds(1_500))
        for sleeper in sleepers { #expect(try await sleeper.value.termination == .exited(0)) }
    }

    @Test func aTaskCancelledBeforeLaunchSpawnsNothing() async throws {
        let spawned = Mutex(false)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.run(
                shell("trap '' INT; sleep 100"), onSpawn: { _ in spawned.withLock { $0 = true } })
        }
        let start = ContinuousClock.now
        await #expect(throws: SubprocessError.cancelled) { try await task.value }
        #expect(!spawned.withLock { $0 })
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }
}

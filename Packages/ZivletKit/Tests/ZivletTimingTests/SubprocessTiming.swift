import EngineTestSupport
import Foundation
import Testing
import ZivletEngineKit

/// The upper bounds of SubprocessRunner's teardown at the production grace (1 s, P1-20), judged by `make timing`
/// below the load limit (D-M7-5). The unit tests check the lower bound and the order of events; these check that a
/// cancel does not take much longer than the grace, alone and while 80 other children run.
@Suite("SubprocessRunner teardown wall time", .enabled(if: TimingGate.isEnabled()), .serialized)
struct SubprocessTiming {
    static let sh = URL(fileURLWithPath: "/bin/sh")
    static let grace = Duration.seconds(1)
    /// The grace plus the reap and the pipes' end: the bound the unit tests used before D-M7-5.
    static let bound = grace + .milliseconds(500)
    let runner = SubprocessRunner(teardownGrace: grace)

    static func shell(_ script: String) -> SubprocessRequest {
        SubprocessRequest(executable: sh, arguments: ["-c", script], stdoutLimit: 1 << 20, stderrTailLimit: 64 << 10)
    }

    @Test func aChildIgnoringSIGINTIsGoneSoonAfterTheGrace() async throws {
        let elapsed = try await cancelIgnoringChild()
        TimingGate.report(
            "SIGINT-ignoring child torn down in \(TimingGate.milliseconds(elapsed)) "
                + "(grace 1000 ms, bound \(TimingGate.milliseconds(Self.bound)))")
        #expect(elapsed >= Self.grace && elapsed < Self.bound)
    }

    @Test func aCancelledGroupWithABackgroundMemberEndsWithinTheBound() async throws {
        let elapsed = try await cancel("sleep 100 & echo ready; sleep 100")
        TimingGate.report(
            "group with a background member torn down in \(TimingGate.milliseconds(elapsed)) "
                + "(bound \(TimingGate.milliseconds(Self.bound)))")
        #expect(elapsed < Self.bound)
    }

    @Test func teardownIsPromptWhileManyOtherChildrenRun() async throws {
        let runner = self.runner
        let sleepers = (0..<80).map { _ in Task { try await runner.run(Self.shell("sleep 30")) } }
        defer { for sleeper in sleepers { sleeper.cancel() } }
        let elapsed = try await cancelIgnoringChild()
        TimingGate.report(
            "teardown beside 80 children in \(TimingGate.milliseconds(elapsed)) "
                + "(bound \(TimingGate.milliseconds(Self.bound)))")
        #expect(elapsed < Self.bound)
    }

    private func cancelIgnoringChild() async throws -> Duration {
        try await cancel("trap '' INT; echo ready; sleep 100")
    }

    /// Starts `script`, waits for its ready line, cancels it and returns the time from the cancel to the task's end.
    private func cancel(_ script: String) async throws -> Duration {
        let ready = Signal()
        let runner = self.runner
        let task = Task { try await runner.run(Self.shell(script), onLine: ready.firing(on: "ready")) }
        await ready.wait()
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: SubprocessError.cancelled) { try await task.value }
        return ContinuousClock.now - start
    }
}

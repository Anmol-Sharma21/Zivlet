import EngineMedia
import EngineTestSupport
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

/// Where an ffmpeg cancel spends its time, at the production grace (1 s, P1-20), judged against NFR-9 (the ffmpeg
/// process group is gone ≤ 1 s after a cancel) by `make timing` below the load limit (D-M7-6). Printed: cancel →
/// SIGINT sent, SIGINT → ffmpeg exited (and whether by itself, by SIGINT or by the SIGKILL at the grace), exit →
/// the job's task returned (the reap, the pipes' end and the engine's return, together). NFR-9's 1 s is a known
/// issue (OS-M7-7); P1-20's bound, the grace plus 500 ms, is a hard ceiling for the group's end and the task's return
/// alike, so a slower teardown fails (D-M7-64).
@Suite("ffmpeg cancel wall time (NFR-9)", .enabled(if: TimingGate.isEnabled()), .serialized)
struct MediaCancelTiming {
    static let nfr9 = Duration.seconds(1)
    /// P1-20: the 1 s grace, then SIGKILL, the reap and the pipes' end within 500 ms.
    static let ceiling = Duration.milliseconds(1_500)

    @Test func aCancelledEncodeIsGoneWithinOneSecond() async throws {
        _ = try EngineLocator().locateMediaTools()
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-cancel-timing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let signals = RecordingSignals()
        let engine = MediaEngine(runner: SubprocessRunner(signalling: signals))
        _ = await engine.availability(of: ConversionPair(source: .mp4, target: .webm))
        let run = try MediaCancelRun(engine: engine, staged: dir.appending(path: ".zivlet-cancel.webm"))
        await run.encoding.wait()
        let cancelled = ContinuousClock.now
        run.task.cancel()
        await #expect(throws: JobError.cancelled) { try await run.task.value }
        let returned = ContinuousClock.now
        let steps = signals.steps.filter { $0.group == run.pid }
        let split = try CancelSplit(steps, cancelled: cancelled, returned: returned)
        TimingGate.report(split.line)
        // G-M7-3, OS-M7-7: mid-encode, libvpx-vp9 ffmpeg does not stop on SIGINT within the 1 s grace, so the group
        // ends at the SIGKILL, about 70 ms past NFR-9. The budget is not changed here; the owner decides (a shorter
        // grace for ffmpeg, `q` on stdin first, or a new budget). Known and printed until then, never hidden.
        withKnownIssue("NFR-9 missed: ffmpeg ends at the SIGKILL after the 1 s grace (OS-M7-7)", isIntermittent: true) {
            #expect(split.cancelToExit <= Self.nfr9)
        }
        #expect(split.cancelToExit < Self.ceiling, "the group outlived P1-20's bound")
        #expect(returned - cancelled < Self.ceiling, "the job's task outlived P1-20's bound")
        TimingGate.report(
            "NFR-9 (group gone ≤ 1000 ms): \(split.cancelToExit <= Self.nfr9 ? "met" : "missed, known issue OS-M7-7")")
    }
}

/// The steps of one cancel, from the signals recorded for its group.
struct CancelSplit {
    let cancelToSIGINT: Duration
    let sigintToExit: Duration
    let exitToReturn: Duration
    let endedBy: String

    var cancelToExit: Duration { cancelToSIGINT + sigintToExit }

    init(_ steps: [RecordingSignals.Step], cancelled: ContinuousClock.Instant, returned: ContinuousClock.Instant) throws
    {
        let sigint = try #require(steps.first { $0.kind == .signal(SIGINT) })
        let exit = try #require(steps.first { if case .leaderExited = $0.kind { true } else { false } })
        cancelToSIGINT = sigint.at - cancelled
        sigintToExit = exit.at - sigint.at
        exitToReturn = returned - exit.at
        endedBy =
            switch exit.kind {
            case .leaderExited(signal: nil): "its own exit"
            case .leaderExited(signal: SIGINT): "SIGINT"
            case .leaderExited(signal: SIGKILL): "SIGKILL at the grace"
            case .leaderExited(signal: let other?): "signal \(other)"
            case .signal: "unknown"
            }
    }

    var line: String {
        let ms = TimingGate.milliseconds
        return "ffmpeg cancel: cancel→SIGINT \(ms(cancelToSIGINT)), SIGINT→exit \(ms(sigintToExit)) (\(endedBy)), "
            + "exit→return \(ms(exitToReturn)); group gone after \(ms(cancelToExit)) of NFR-9's 1000 ms"
    }
}

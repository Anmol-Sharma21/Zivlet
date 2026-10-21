import EngineTestSupport
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

/// ffmpeg that reports one progress block and then hangs until it is torn down.
struct HangingFFmpeg: ProcessRunning {
    let base: FakeRunner

    func run(
        _ request: SubprocessRequest, onSpawn: @escaping @Sendable (Int32) -> Void,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws(SubprocessError) -> SubprocessResult {
        guard request.arguments.contains("-progress") else {
            return try await base.run(request, onSpawn: onSpawn, onLine: onLine)
        }
        onSpawn(FakeRunner.fakePID)
        onLine("out_time_us=1000")
        onLine("progress=continue")
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        throw .cancelled
    }
}

@Suite("ffmpeg stall watchdog: out_time flat for 60 s stops the encode (P1-07, 03a §4.6)")
struct StallWatchTests {
    @Test func flatOutputTimeForTheWholeLimitIsAStall() {
        let watch = StallWatch(limit: .seconds(60), start: .seconds(10))
        #expect(!watch.isStalled(at: .seconds(69)))
        #expect(watch.isStalled(at: .seconds(70)))
    }

    @Test func advancingOutputTimeResetsTheWatchButARepeatOrAMissingValueDoesNot() {
        let advanced = StallWatch(limit: .seconds(60), start: .zero).observing(outTimeMicros: 1_000, at: .seconds(30))
        #expect(!advanced.isStalled(at: .seconds(89)))
        let flat = advanced.observing(outTimeMicros: 1_000, at: .seconds(50)).observing(
            outTimeMicros: nil, at: .seconds(55))
        #expect(flat.isStalled(at: .seconds(90)))
        #expect(!flat.observing(outTimeMicros: 2_000, at: .seconds(85)).isStalled(at: .seconds(90)))
    }

    /// A palette pass writes nothing until it has read the whole input, so before the first `out_time` the watch
    /// allows the longer startup limit; after it, the normal limit applies.
    @Test func beforeTheFirstOutputTimeTheStartupLimitApplies() {
        let watch = StallWatch(limit: .seconds(60), start: .zero, startupLimit: .seconds(200))
        #expect(!watch.observing(outTimeMicros: nil, at: .seconds(100)).isStalled(at: .seconds(199)))
        #expect(watch.isStalled(at: .seconds(200)))
        let moving = watch.observing(outTimeMicros: 1, at: .seconds(150))
        #expect(!moving.isStalled(at: .seconds(209)) && moving.isStalled(at: .seconds(210)))
        #expect(
            StallWatch(limit: .seconds(60), start: .zero, startupLimit: .seconds(5)).isStalled(at: .seconds(59))
                == false)
    }

    @Test func aPalettePassMayDecodeTheWholeInputBeforeItsFirstOutputTime() {
        let policy = StallPolicy.standard
        let palette = FFmpegStage(
            argv: ["-filter_complex", "[0:0]fps=10," + GIFPlanner.paletteTail + "bayer"],
            expectedDurationMicros: 600_000_000)
        #expect(MediaEngine.startupLimit(palette, policy: policy) == .seconds(660))
        let plain = FFmpegStage(argv: ["-c:a", "libmp3lame"], expectedDurationMicros: 600_000_000)
        #expect(MediaEngine.startupLimit(plain, policy: policy) == .seconds(60))
        let unknown = FFmpegStage(argv: palette.argv, expectedDurationMicros: nil)
        #expect(MediaEngine.startupLimit(unknown, policy: policy) == .seconds(60))
    }

    @Test func aMonitorWaitsOutTheStartupLimitButNotTheNormalOne() async throws {
        let policy = StallPolicy(limit: .milliseconds(100), interval: .milliseconds(10))
        let patient = StallMonitor(policy: policy, startupLimit: .seconds(5))
        let value = try await patient.guarding { () async throws(JobError) in
            try? await Task.sleep(for: .milliseconds(300))
            return 1
        }
        #expect(value == 1)
        let strict = StallMonitor(policy: policy, startupLimit: policy.limit)
        await #expect(throws: JobError.stalled) {
            try await strict.guarding { () async throws(JobError) in
                try? await Task.sleep(for: .seconds(2))
                return 1
            }
        }
    }

    @Test func anEncodeWhoseOutputTimeStopsIsTornDownAsStalled() async throws {
        let rig = try MediaRig(probes: ["tone.wav": MediaEngineTests.wav])
        let engine = MediaEngine(
            locator: rig.locator, runner: HangingFFmpeg(base: rig.runner),
            stall: StallPolicy(limit: .milliseconds(150), interval: .milliseconds(10)))
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await engine.prepare(request, workspace: rig.workspace(request))
        let start = ContinuousClock.now
        await #expect(throws: JobError.stalled) { try await engine.execute(plan, context: ExecutionContext()) }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func cancellingTheJobStillReportsCancelledNotStalled() async throws {
        let rig = try MediaRig(probes: ["tone.wav": MediaEngineTests.wav])
        let engine = MediaEngine(locator: rig.locator, runner: HangingFFmpeg(base: rig.runner))
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await engine.prepare(request, workspace: rig.workspace(request))
        let task = Task { try await engine.execute(plan, context: ExecutionContext()) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: JobError.cancelled) { try await task.value }
    }
}

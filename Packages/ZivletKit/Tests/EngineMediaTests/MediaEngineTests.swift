import EngineTestSupport
import Foundation
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

@Suite("MediaEngine prepare / execute / verify with a scripted ffmpeg (P1-23)")
struct MediaEngineTests {
    static let wav = ProbeJSON.file(
        "wav", duration: "\"1.0\"",
        ProbeJSON.stream(0, "audio", "pcm_s16le", #","sample_rate":"44100","channels":1,"bits_per_raw_sample":"16""#))
    static let mp3 = ProbeJSON.file("mp3", duration: "\"1.02\"", ProbeJSON.stream(0, "audio", "mp3"))
    static let hdrMov = ProbeJSON.file(
        "mov,mp4,m4a,3gp,3g2,mj2",
        ProbeJSON.stream(
            0, "video", "hevc", #","width":64,"height":64,"pix_fmt":"yuv420p10le","color_transfer":"smpte2084""#))

    @Test func preparePlansFromTheWhitelistedProbe() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav])
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        #expect(plan.engine == .media && plan.lanes == [.audio] && plan.outputFormat == .mp3 && plan.notes.isEmpty)
        let stage = try #require(plan.stages.first.flatMap(\.ffmpeg))
        #expect(stage.argv.contains(subsequence: ["-c:a", "libmp3lame"]))
        #expect(stage.argv.last == "file:" + rig.workspace(request).stagedFile.path)
        #expect(stage.expectedDurationMicros == 1_000_000)
        let probe = try #require(rig.runner.requests.first { $0.executable.lastPathComponent == "ffprobe" })
        #expect(probe.arguments.contains("-format_whitelist"))
    }

    @Test func aTargetWithoutItsEncoderIsUnavailableBeforeAnyProbe() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav])
        let request = try rig.request("tone.wav", .wav, to: .ogg)
        await #expect(throws: JobError.routeUnavailable(.wav, .ogg, ["libvorbis"])) {
            try await rig.engine.prepare(request, workspace: rig.workspace(request))
        }
        #expect(!rig.runner.requests.contains { $0.executable.lastPathComponent == "ffprobe" })
    }

    @Test func aFileThatNeedsAMissingFilterIsUnavailable() async throws {
        let rig = try MediaRig(probes: ["hdr.mov": Self.hdrMov])
        let request = try rig.request("hdr.mov", .mov, to: .webm)
        await #expect(throws: JobError.routeUnavailable(.mov, .webm, ["zscale"])) {
            try await rig.engine.prepare(request, workspace: rig.workspace(request))
        }
    }

    @Test(arguments: [
        ("hls", JobError.unsupportedInput(.contentMismatch)), ("", .unsupportedInput(.unreadable)),
    ])
    func probeFailuresAreTypedInputErrors(formatName: String, expected: JobError) async throws {
        let json = formatName.isEmpty ? "{" : ProbeJSON.file(formatName, ProbeJSON.h264)
        let rig = try MediaRig(probes: ["clip.mp4": json])
        let request = try rig.request("clip.mp4", .mp4, to: .mov)
        await #expect(throws: expected) { try await rig.engine.prepare(request, workspace: rig.workspace(request)) }
    }

    @Test func anUnreadableFileAndAMissingTrackAreInputErrors() async throws {
        let rig = try MediaRig(probes: ["silent.mp4": ProbeJSON.file("mov,mp4,m4a,3gp,3g2,mj2", ProbeJSON.h264)])
        let missing = try rig.request("absent.mp4", .mp4, to: .mov)
        await #expect(throws: JobError.unsupportedInput(.unreadable)) {
            try await rig.engine.prepare(missing, workspace: rig.workspace(missing))
        }
        let silent = try rig.request("silent.mp4", .mp4, to: .mp3)
        await #expect(throws: JobError.unsupportedInput(.noAudioTrack)) {
            try await rig.engine.prepare(silent, workspace: rig.workspace(silent))
        }
    }

    @Test func gifIntoAnOpaqueTargetNotesTheFlattenedAlpha() async throws {
        let gif = ProbeJSON.file(
            "gif", ProbeJSON.stream(0, "video", "gif", #","width":64,"height":64,"pix_fmt":"bgra""#))
        let rig = try MediaRig(probes: ["a.gif": gif])
        let request = try rig.request("a.gif", .gif, to: .mp4)
        #expect(try await rig.engine.prepare(request, workspace: rig.workspace(request)).notes == [.alphaFlattened])
    }

    /// A hostile, highly compressible input must not fill the volume: each pass gets `-fs` at the job's byte limit,
    /// and an output that reaches it is reported as a full disk rather than a short file.
    @Test func everyPassIsCappedAtTheOutputByteLimit() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav])
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        _ = try rig.staged(request, bytes: 321)
        _ = try await rig.engine.execute(plan, context: ExecutionContext(outputByteLimit: 5_000_000))
        let argv = try #require(rig.runner.requests.last { $0.arguments.contains("-progress") }?.arguments)
        let cap = try #require(argv.firstIndex(of: "-fs"))
        #expect(argv[cap + 1] == "5000000" && cap < argv.count - 2 && argv.last?.hasPrefix("file:") == true)
        _ = try rig.staged(request, bytes: 2_000_000)
        await #expect(throws: JobError.diskFull) {
            try await rig.engine.execute(plan, context: ExecutionContext(outputByteLimit: 2_000_000))
        }
    }

    /// ffmpeg follows a symlink at its output path, so a staged file swapped for one is refused before ffmpeg starts.
    @Test func aStagedFileSwappedForASymlinkIsRefusedBeforeFFmpegRuns() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav])
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        let victim = rig.dir.appending(path: "victim.txt")
        try Data("precious".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(at: plan.stagedFile, withDestinationURL: victim)
        await #expect(throws: JobError.verificationFailed(StagedFile.replacedMessage)) {
            try await rig.engine.execute(plan, context: ExecutionContext())
        }
        #expect(!rig.runner.requests.contains { $0.arguments.contains("-progress") })
    }

    @Test func executeReportsProgressAndTheChildPID() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav])
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        _ = try rig.staged(request, bytes: 321)
        let seen = Mutex<(fractions: [Double?], pid: Int32)>(([], 0))
        let context = ExecutionContext(
            progress: ProgressSink(interval: .zero) { progress in
                seen.withLock { $0.fractions.append(progress.fraction) }
            },
            spawned: { pid in seen.withLock { $0.pid = pid } })
        let output = try await rig.engine.execute(plan, context: context)
        #expect(output == StagedOutput(format: .mp3, url: plan.stagedFile, byteCount: 321))
        #expect(seen.withLock { $0.fractions } == [0.5, 1.0])
        #expect(seen.withLock { $0.pid } == FakeRunner.fakePID)
    }

    @Test func progressCarriesTheStageBytesAndTimeLeft() async throws {
        let progress = "total_size=4096\nout_time_us=3000000\nspeed=2.0x\nprogress=continue\nprogress=end\n"
        let rig = try MediaRig(probes: ["tone.wav": Self.wav], ffmpeg: FakeRunner.result(progress))
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        _ = try rig.staged(request, bytes: 321)
        let seen = Mutex<[JobProgress]>([])
        let context = ExecutionContext(progress: ProgressSink(interval: .zero) { p in seen.withLock { $0.append(p) } })
        _ = try await rig.engine.execute(plan, context: context)
        let first = try #require(seen.withLock { $0 }.first)
        #expect(first.bytesWritten == 4096 && first.stage == 0 && first.stageCount == plan.stages.count)
        #expect(first.eta != nil)
    }

    @Test(arguments: [
        (FakeRunner.result("", status: 1, stderr: "x: No space left on device"), JobError.diskFull),
        (FakeRunner.result("", status: 69, stderr: "boom"), .processFailed(status: 69, stderrTail: "boom")),
        (
            SubprocessResult(termination: .signaled(11), stdout: Data(), stdoutTruncated: false, stderrTail: ""),
            .crashed(signal: 11)
        ),
    ])
    func executeMapsFailures(result: SubprocessResult, expected: JobError) async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav], ffmpeg: result)
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        await #expect(throws: expected) { try await rig.engine.execute(plan, context: ExecutionContext()) }
    }

    @Test func verifyAcceptsAMatchingOutput() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav, "staged": Self.mp3])
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        try await rig.engine.verify(try rig.staged(request), plan: plan)
    }

    @Test(arguments: [
        ProbeJSON.file("mp3", duration: "\"9.0\""), ProbeJSON.file("wav", ProbeJSON.stream(0, "audio", "pcm_s16le")),
        ProbeJSON.file("mp3", duration: "\"1.0\"", ProbeJSON.stream(0, "video", "mjpeg")), "{",
    ])
    func verifyRefusesAWrongOutput(staged: String) async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav, "staged": staged])
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        await #expect(throws: JobError.self) { try await rig.engine.verify(try rig.staged(request), plan: plan) }
    }

    @Test func verifyRefusesAnEmptyFile() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav, "staged": Self.mp3])
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        await #expect(throws: JobError.verificationFailed("The output file is empty.")) {
            try await rig.engine.verify(try rig.staged(request, bytes: 0), plan: plan)
        }
    }

    @Test func availabilityFollowsTheProbedEncoders() async throws {
        let rig = try MediaRig(probes: [:])
        #expect(await rig.engine.availability(of: ConversionPair(source: .wav, target: .mp3)) == .available)
        #expect(
            await rig.engine.availability(of: ConversionPair(source: .mp3, target: .ogg)) == .unavailable(["libvorbis"])
        )
        let none = try MediaRig(probes: [:], locates: false)
        #expect(
            await none.engine.availability(of: ConversionPair(source: .wav, target: .mp3)) == .unavailable(["ffmpeg"]))
    }

    /// A helper that could not start (EMFILE) does not hide routes; the job reports the real cause.
    @Test func aHelperThatCannotStartIsReportedAsSuchNotAsMissing() async throws {
        let rig = try MediaRig(probes: [:])
        let engine = MediaEngine(
            locator: rig.locator, runner: FakeRunner(failure: .launchFailed(errno: EMFILE)), integrity: rig.integrity)
        #expect(await engine.availability(of: ConversionPair(source: .wav, target: .mp3)) == .available)
        let request = try JobRequest(
            input: try rig.input("a.wav", .wav), operation: .convert(.mp3), destination: rig.dir)
        let workspace = JobWorkspace(job: request.id, stagedFile: rig.dir.appending(path: ".zivlet-x.mp3"))
        await #expect(throws: JobError.helperFailed(errno: EMFILE)) {
            try await engine.prepare(request, workspace: workspace)
        }
    }

    @Test func concurrentFirstJobsProbeTheToolsOnce() async throws {
        let rig = try MediaRig(probes: [:], delay: .milliseconds(20))
        let engine = rig.engine
        let pair = ConversionPair(source: .wav, target: .mp3)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = await engine.availability(of: pair) } }
        }
        let lists = rig.runner.requests.filter { ["-encoders", "-filters"].contains($0.arguments.last ?? "") }
        #expect(lists.count == 2)
    }

    /// A11: a bundled helper whose signature fails hides the media routes and fails jobs with a reinstall message.
    @Test func aDamagedHelperHidesTheRoutesAndFailsJobs() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav], integrity: CountingIntegrity(fails: true))
        #expect(
            await rig.engine.availability(of: ConversionPair(source: .wav, target: .mp3)) == .unavailable(["signature"])
        )
        let request = try rig.request("tone.wav", .wav, to: .mp3)
        await #expect(throws: JobError.engineDamaged(.media)) {
            try await rig.engine.prepare(request, workspace: rig.workspace(request))
        }
        #expect(!rig.runner.requests.contains { $0.executable.lastPathComponent == "ffprobe" })
    }

    @Test func concurrentFirstJobsCheckTheHelpersOnce() async throws {
        let rig = try MediaRig(probes: ["tone.wav": Self.wav], delay: .milliseconds(20))
        let (engine, request) = (rig.engine, try rig.request("tone.wav", .wav, to: .mp3))
        let workspace = rig.workspace(request)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try? await engine.prepare(request, workspace: workspace) } }
        }
        #expect(rig.integrity.calls == 1)
    }

    @Test func handlesMediaPairsOnly() throws {
        let engine = try MediaRig(probes: [:]).engine
        #expect(engine.handles(ConversionPair(source: .mov, target: .mp3)))
        #expect(engine.handles(ConversionPair(source: .gif, target: .webm)))
        #expect(!engine.handles(ConversionPair(source: .jpg, target: .png)))
        #expect(!engine.handles(ConversionPair(source: .mp4, target: .jpg)))
    }
}

@Suite("Every one of the 104 media pairs plans, and capability gaps are typed (P1-23)")
struct MediaPairSweepTests {
    static let registry = FormatRegistry.standard
    static let pairs = ConversionCatalog.standard.pairs.filter { pair in
        let media: Set<FormatCategory> = [.audio, .video, .gif]
        return media.contains(registry.format(pair.source).category)
            && media.contains(registry.format(pair.target).category)
    }

    static func plan(_ pair: ConversionPair, _ caps: FFmpegCapabilities) throws(JobError) -> FFmpegPlan {
        let input = try InputItem(
            url: URL(fileURLWithPath: "/in/x.\(pair.source.rawValue)"), format: pair.source, byteCount: 1)
        let request = try JobRequest(
            input: input, operation: .convert(pair.target), destination: URL(fileURLWithPath: "/in"))
        let tools = ResolvedTools(
            tools: MediaTools(directory: URL(fileURLWithPath: "/t"), origin: .development), capabilities: caps)
        return try MediaEngine.plan(
            request, info: RepresentativeProbe.info(for: pair.source),
            staged: URL(fileURLWithPath: "/in/.zivlet-1.\(pair.target.rawValue)"), resolved: tools)
    }

    @Test func thereAre104MediaPairs() { #expect(Self.pairs.count == 104) }

    @Test(arguments: pairs)
    func everyPairPlansWithAFullBuild(pair: ConversionPair) throws {
        #expect(try !Self.plan(pair, HomebrewLists.full).passes.isEmpty)
    }

    @Test(arguments: pairs)
    func aHomebrewBuildLosesOnlyTheVorbisTarget(pair: ConversionPair) {
        let gate = MediaRouteGate.availability(pair, capabilities: HomebrewLists.capabilities)
        if pair.target == .ogg {
            #expect(gate == .unavailable(["libvorbis"]))
            #expect(throws: JobError.routeUnavailable(pair.source, .ogg, ["libvorbis"])) {
                try Self.plan(pair, HomebrewLists.capabilities)
            }
        } else {
            #expect(gate == .available)
        }
    }

    @Test func requirementsAreReadFromTheArgv() {
        let graph = "[0:0]fps=15,scale='min(480,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
        #expect(FFmpegRequirements.filterNames(graph) == ["fps", "scale", "split", "palettegen", "paletteuse"])
        let argv = [
            "-map", "0:0", "-c:v", "libx264", "-c:a:1", "aac_at", "-c", "copy", "-vf",
            FFmpegArgs.toneMapToSDR(HDRSignal(Fx.video(0, "hevc", hdr: true))),
        ]
        #expect(FFmpegRequirements.encoders(in: argv) == ["libx264", "aac_at"])
        #expect(FFmpegRequirements.filters(in: argv) == ["zscale", "format", "tonemap"])
    }

    @Test func noVideoToolboxMeansTheLibx264Fallback() {
        let caps = FFmpegCapabilities(encoders: ["h264_videotoolbox"], filters: [])
        #expect(!MediaCapabilities(caps).videoToolbox)
        #expect(MediaCapabilities(HomebrewLists.capabilities).videoToolbox)
    }
}

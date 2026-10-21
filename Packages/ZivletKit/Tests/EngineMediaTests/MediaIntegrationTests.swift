import AVFoundation
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

/// Real conversions (P1-23, P1-60 subset): runs when a local ffmpeg is found (ZIVLET_FFMPEG_DIR, or Homebrew in
/// Debug test builds) and is skipped otherwise. Fixtures are synthesized with lavfi, one per source format, once.
enum MediaIntegration {
    static let tools: MediaTools? = try? EngineLocator().locateMediaTools()

    /// lavfi synthesis per source format: 1 s, 64 × 48, 10 fps, a 44.1 kHz tone.
    static func synthesis(_ format: FormatID) -> (args: [String], needs: [String]) {
        let video = ["-f", "lavfi", "-i", "testsrc=d=1:s=64x48:r=10"]
        let tone = ["-f", "lavfi", "-i", "sine=d=1:sample_rate=44100"]
        switch format {
        case .mp3: return (tone + ["-c:a", "libmp3lame"], ["libmp3lame"])
        case .m4a: return (tone + ["-c:a", "aac"], ["aac"])
        case .wav: return (tone + ["-c:a", "pcm_s16le"], [])
        case .flac: return (tone + ["-c:a", "flac"], ["flac"])
        case .ogg: return (tone + ["-c:a", "vorbis", "-strict", "experimental", "-ac", "2"], ["vorbis"])
        case .opus: return (tone + ["-c:a", "libopus"], ["libopus"])
        case .aiff: return (tone + ["-c:a", "pcm_s16be"], [])
        case .wma: return (tone + ["-c:a", "wmav2"], ["wmav2"])
        case .webm: return (video + tone + ["-c:v", "libvpx-vp9", "-c:a", "libopus"], ["libvpx-vp9", "libopus"])
        case .avi: return (video + tone + ["-c:v", "mpeg4", "-c:a", "libmp3lame"], ["mpeg4", "libmp3lame"])
        case .wmv: return (video + tone + ["-c:v", "wmv2", "-c:a", "wmav2"], ["wmv2", "wmav2"])
        case .gif: return (video + ["-c:v", "gif"], ["gif"])
        default: return (video + tone + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac"], ["libx264", "aac"])
        }
    }
}

/// Synthesizes each source once per test run. The actor is reentrant across the ffmpeg await, so concurrent tests for
/// one source share the in-flight synthesis instead of starting a second `-y` run that truncates the file under the
/// first test.
actor FixtureFactory {
    static let shared = FixtureFactory()
    private var made: [FormatID: Task<URL?, any Error>] = [:]
    private let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-fixtures-\(UUID().uuidString)")

    func fixture(_ format: FormatID, tools: MediaTools, capabilities: FFmpegCapabilities) async throws -> URL? {
        if let pending = made[format] { return try await pending.value }
        let dir = self.dir
        let task = Task { try await Self.synthesize(format, into: dir, tools: tools, capabilities: capabilities) }
        made[format] = task
        return try await task.value
    }

    private static func synthesize(
        _ format: FormatID, into dir: URL, tools: MediaTools, capabilities: FFmpegCapabilities
    ) async throws -> URL? {
        let (args, needs) = MediaIntegration.synthesis(format)
        guard capabilities.missing(encoders: needs).isEmpty else { return nil }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "source.\(FormatRegistry.standard.format(format).canonicalExtension)")
        let request = SubprocessRequest(
            executable: tools.ffmpeg, arguments: ["-hide_banner", "-loglevel", "error", "-y"] + args + [url.path])
        let result = try await SubprocessRunner().run(request)
        guard result.termination == .exited(0) else { throw SynthesisFailed(format: format, stderr: result.stderrTail) }
        return url
    }
}

/// Thrown out of the shared synthesis task, so every test waiting on it fails with the same reason.
struct SynthesisFailed: Error, CustomStringConvertible {
    let format: FormatID
    let stderr: String
    var description: String { "synthesis of \(format): \(stderr)" }
}

@Suite(
    "Real ffmpeg conversions for all 104 media pairs (opt-in: needs a local ffmpeg)",
    .enabled(if: MediaIntegration.tools != nil))
struct MediaIntegrationTests {
    static let engine = MediaEngine()

    @Test(arguments: MediaPairSweepTests.pairs)
    func convertsVerifiesAndPlays(pair: ConversionPair) async throws {
        let tools = try #require(MediaIntegration.tools)
        let caps = try await CapabilityProbe(tools: tools, cacheDirectory: nil).capabilities()
        guard let source = try await FixtureFactory.shared.fixture(pair.source, tools: tools, capabilities: caps) else {
            withKnownIssue("this ffmpeg cannot synthesize \(pair.source)") { Issue.record("not run") }
            return
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try InputItem(url: source, format: pair.source, byteCount: 1)
        let request = try JobRequest(input: input, operation: .convert(pair.target), destination: dir)
        let workspace = JobWorkspace(job: request.id, stagedFile: dir.appending(path: ".zivlet-\(request.id).out"))
        let gate = MediaRouteGate.availability(pair, capabilities: caps)
        if case .unavailable(let missing) = gate {
            await #expect(throws: JobError.routeUnavailable(pair.source, pair.target, missing)) {
                try await Self.engine.prepare(request, workspace: workspace)
            }
            return
        }
        let plan = try await Self.engine.prepare(request, workspace: workspace)
        let output = try await Self.engine.execute(plan, context: ExecutionContext())
        try await Self.engine.verify(output, plan: plan)
        if [.mp4, .mov].contains(pair.target) { try await Self.expectPlayable(output.url, type: pair.target) }
    }

    /// AVFoundation needs a recognisable extension, so the staged file is linked under one first (03b §5.9).
    static func expectPlayable(_ url: URL, type: FormatID) async throws {
        let named = url.deletingLastPathComponent().appending(path: "playable.\(type.rawValue)")
        try FileManager.default.linkItem(at: url, to: named)
        #expect(try await AVURLAsset(url: named).load(.isPlayable), "\(type) output not playable")
    }

    @Test func cancellingARunningEncodeStopsFFmpegQuickly() async throws {
        let tools = try #require(MediaIntegration.tools)
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let staged = dir.appending(path: ".zivlet-cancel.webm")
        let argv = [
            "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats", "-f", "lavfi",
            "-i", "testsrc2=d=600:s=1280x720:r=30", "-c:v", "libvpx-vp9", "-f", "webm", "file:" + staged.path,
        ]
        let plan = try ExecutionPlan(
            engine: .media, stages: [.ffmpeg(FFmpegStage(argv: argv, expectedDurationMicros: 600_000_000))],
            stageWeights: [1], lanes: [.swVideo], outputFormat: .webm, stagedFile: staged)
        // Resolve the tools first and cancel only once ffmpeg runs, so the timing covers the helper teardown and not
        // a capability probe that is still starting under load.
        let engine = MediaEngine()
        _ = await engine.availability(of: ConversionPair(source: .mp4, target: .webm))
        let spawned = AsyncStream.makeStream(of: Int32.self)
        let context = ExecutionContext(spawned: { spawned.continuation.yield($0) })
        let task = Task { try await engine.execute(plan, context: context) }
        var pids = spawned.stream.makeAsyncIterator()
        _ = await pids.next()
        try await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: JobError.cancelled) { try await task.value }
        #expect(ContinuousClock.now - start < .milliseconds(1_500))
        _ = tools
    }
}

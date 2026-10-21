import EngineTestSupport
import Foundation
import Testing
import ZivletCore

@testable import ZivletEngineKit

enum CapabilityFixtures {
    static let encoders = """
        Encoders:
         V..... = Video
         A..... = Audio
         ------
         V....D h264_videotoolbox    VideoToolbox H.264 Encoder (codec h264)
         V....D libvpx-vp9           libvpx VP9 (codec vp9)
         A..... aac_at               aac (AudioToolbox) (codec aac)
         A....D libopus              libopus Opus (codec opus)

        """
    static let filters = """
        Filters:
          T.. = Timeline support
          | = Source or sink filter
          ------
         .. palettegen        V->V       Find the optimal palette for a given stream.
         .S tonemap           V->V       Conversion to/from different dynamic ranges.
         .. color             |->V       Provide an uniformly colored input.
        """
}

@Suite("Capability parsing and the cached probe (P1-11, P1-22)")
struct CapabilityProbeTests {
    /// A directory with a stand-in `ffmpeg` file: the cache key hashes its bytes.
    static func tools(binary: String = "fake ffmpeg") throws -> MediaTools {
        let dir = try cacheDirectory()
        try Data(binary.utf8).write(to: dir.appending(path: "ffmpeg"))
        return MediaTools(directory: dir, origin: .development)
    }

    static func runner() -> FakeRunner {
        FakeRunner(replies: [
            "-encoders": FakeRunner.result(CapabilityFixtures.encoders),
            "-filters": FakeRunner.result(CapabilityFixtures.filters),
        ])
    }

    static func cacheDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-caps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func parsesTheNamesBelowTheRuler() {
        let caps = FFmpegCapabilities.parse(
            encoderList: CapabilityFixtures.encoders, filterList: CapabilityFixtures.filters)
        #expect(caps.encoders == ["h264_videotoolbox", "libvpx-vp9", "aac_at", "libopus"])
        #expect(caps.filters == ["palettegen", "tonemap", "color"])
    }

    @Test func missingListsWhatIsAbsentInOrder() {
        let caps = FFmpegCapabilities(encoders: ["aac_at"], filters: ["scale"])
        #expect(
            caps.missing(encoders: ["libvorbis", "aac_at"], filters: ["zscale", "scale"]) == ["libvorbis", "zscale"])
    }

    @Test func garbageParsesToNothing() {
        #expect(FFmpegCapabilities.parse(encoderList: "no ruler here\n x y", filterList: "").encoders.isEmpty)
    }

    @Test func aSecondProbeWithTheSameBinaryAndOSReadsTheCache() async throws {
        let (dir, tools) = (try Self.cacheDirectory(), try Self.tools())
        let first = Self.runner()
        let caps = try await CapabilityProbe(tools: tools, runner: first, cacheDirectory: dir, osBuild: "26A1")
            .capabilities()
        #expect(first.launchCount == 2)
        let second = Self.runner()
        let again = try await CapabilityProbe(tools: tools, runner: second, cacheDirectory: dir, osBuild: "26A1")
            .capabilities()
        #expect(again == caps)
        #expect(second.launchCount == 0)
    }

    @Test func anotherOSBuildProbesAgainAndMemoryCachesWithinOneProbe() async throws {
        let (dir, tools) = (try Self.cacheDirectory(), try Self.tools())
        _ = try await CapabilityProbe(tools: tools, runner: Self.runner(), cacheDirectory: dir, osBuild: "26A1")
            .capabilities()
        let runner = Self.runner()
        let probe = CapabilityProbe(tools: tools, runner: runner, cacheDirectory: dir, osBuild: "27A1")
        _ = try await probe.capabilities()
        _ = try await probe.capabilities()
        #expect(runner.launchCount == 2)
    }

    @Test func concurrentFirstCallsShareOneProbe() async throws {
        let tools = try Self.tools()
        let runner = FakeRunner(
            replies: [
                "-encoders": FakeRunner.result(CapabilityFixtures.encoders),
                "-filters": FakeRunner.result(CapabilityFixtures.filters),
            ], delay: .milliseconds(20))
        let probe = CapabilityProbe(tools: tools, runner: runner, cacheDirectory: nil, osBuild: "26A1")
        let results = try await withThrowingTaskGroup(of: FFmpegCapabilities.self) { group in
            for _ in 0..<8 { group.addTask { try await probe.capabilities() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == 8 && Set(results.map(\.encoders)).count == 1)
        #expect(runner.launchCount == 2)
    }

    @Test func aFailedProbeIsNotCached() async throws {
        let tools = try Self.tools()
        let failing = FakeRunner(failure: .launchFailed(errno: ENOENT))
        let probe = CapabilityProbe(tools: tools, runner: failing, cacheDirectory: nil, osBuild: "26A1")
        await #expect(throws: JobError.engineMissing(.media)) { try await probe.capabilities() }
        await #expect(throws: JobError.engineMissing(.media)) { try await probe.capabilities() }
        #expect(failing.launchCount == 2)
    }

    @Test func tooManyOpenFilesIsNotAMissingEngine() async throws {
        let failing = FakeRunner(failure: .launchFailed(errno: EMFILE))
        let probe = CapabilityProbe(tools: try Self.tools(), runner: failing, cacheDirectory: nil, osBuild: "26A1")
        await #expect(throws: JobError.helperFailed(errno: EMFILE)) { try await probe.capabilities() }
    }

    /// ffmpeg exiting 0 without its lists (or with a cut list) must not be cached as "can do nothing".
    @Test(arguments: [
        FakeRunner.result("no ruler here"),
        SubprocessResult(
            termination: .exited(0), stdout: Data(CapabilityFixtures.encoders.utf8), stdoutTruncated: true,
            stderrTail: ""),
    ])
    func anUnreadableListIsAFailureAndIsNotCached(encoders: SubprocessResult) async throws {
        let (dir, tools) = (try Self.cacheDirectory(), try Self.tools())
        let runner = FakeRunner(replies: [
            "-encoders": encoders, "-filters": FakeRunner.result(CapabilityFixtures.filters),
        ])
        let probe = CapabilityProbe(tools: tools, runner: runner, cacheDirectory: dir, osBuild: "26A1")
        await #expect(throws: JobError.self) { try await probe.capabilities() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func aCachedEmptyListIsProbedAgain() async throws {
        let (dir, tools) = (try Self.cacheDirectory(), try Self.tools())
        let probe = CapabilityProbe(tools: tools, runner: Self.runner(), cacheDirectory: dir, osBuild: "26A1")
        let file = try #require(try await probe.cacheFile())
        try JSONEncoder().encode(FFmpegCapabilities(encoders: [], filters: [])).write(to: file)
        let runner = Self.runner()
        let caps = try await CapabilityProbe(tools: tools, runner: runner, cacheDirectory: dir, osBuild: "26A1")
            .capabilities()
        #expect(runner.launchCount == 2 && caps.encoders.contains("libopus"))
    }

    @Test func aCorruptCacheFileIsReplaced() async throws {
        let (dir, tools) = (try Self.cacheDirectory(), try Self.tools())
        let probe = CapabilityProbe(tools: tools, runner: Self.runner(), cacheDirectory: dir, osBuild: "26A1")
        let file = try #require(try await probe.cacheFile())
        try Data("not json".utf8).write(to: file)
        #expect(try await probe.capabilities().encoders.contains("aac_at"))
        #expect(try JSONDecoder().decode(FFmpegCapabilities.self, from: Data(contentsOf: file)).filters.count == 3)
    }

    @Test func aFailingListIsAProcessFailure() async throws {
        let tools = try Self.tools()
        let runner = FakeRunner(replies: ["-encoders": FakeRunner.result("", status: 1, stderr: "bad")])
        let probe = CapabilityProbe(tools: tools, runner: runner, cacheDirectory: nil, osBuild: "26A1")
        await #expect(throws: JobError.processFailed(status: 1, stderrTail: "bad")) { try await probe.capabilities() }
    }

    @Test func aToolThatCannotLaunchIsAMissingEngine() async throws {
        let tools = try Self.tools()
        let probe = CapabilityProbe(
            tools: tools, runner: FakeRunner(failure: .launchFailed(errno: ENOENT)), cacheDirectory: nil,
            osBuild: "26A1")
        await #expect(throws: JobError.engineMissing(.media)) { try await probe.capabilities() }
    }

    @Test func anUnreadableBinaryWithACacheIsAMissingEngine() async throws {
        let tools = MediaTools(directory: URL(fileURLWithPath: "/nonexistent"), origin: .development)
        let probe = CapabilityProbe(
            tools: tools, runner: Self.runner(), cacheDirectory: try Self.cacheDirectory(), osBuild: "1")
        await #expect(throws: JobError.engineMissing(.media)) { try await probe.capabilities() }
    }

    @Test func theCurrentOSBuildIsKnown() {
        #expect(!CapabilityProbe.currentOSBuild().isEmpty)
    }
}

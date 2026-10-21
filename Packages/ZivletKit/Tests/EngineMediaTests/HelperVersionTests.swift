import EngineTestSupport
import Testing
import ZivletEngineKit

@testable import EngineMedia

@Suite("Helper versions for Settings › Advanced (D3)")
struct MediaHelperVersionTests {
    static let banner = "ffmpeg version 9.0.2 Copyright (c) 2000-2026 the FFmpeg developers\nbuilt with Apple clang\n"

    @Test func theVersionIsTheWordAfterFFmpegVersion() {
        #expect(FFmpegVersion.parse(Self.banner) == "9.0.2")
        #expect(FFmpegVersion.parse("ffmpeg version n9.1-dev-123\n") == "n9.1-dev-123")
        #expect(FFmpegVersion.parse("something else\n") == nil)
        #expect(FFmpegVersion.parse("") == nil)
    }

    @Test func theEngineAsksTheCheckedHelper() async throws {
        let rig = try MediaRig(probes: [:], ffmpeg: FakeRunner.result(Self.banner))
        #expect(await rig.engine.helperVersions() == [HelperVersion(name: "FFmpeg", version: "9.0.2")])
        #expect(rig.integrity.calls == 1)
        #expect(rig.runner.requests.last?.arguments == ["-hide_banner", "-version"])
    }

    @Test func aMissingOrDamagedHelperHasNoVersion() async throws {
        let missing = try MediaRig(probes: [:], locates: false)
        #expect(await missing.engine.helperVersions() == [HelperVersion(name: "FFmpeg", version: nil)])
        let damaged = try MediaRig(probes: [:], integrity: CountingIntegrity(fails: true))
        #expect(await damaged.engine.helperVersions() == [HelperVersion(name: "FFmpeg", version: nil)])
        let failing = try MediaRig(probes: [:], ffmpeg: FakeRunner.result("", status: 1))
        #expect(await failing.engine.helperVersions() == [HelperVersion(name: "FFmpeg", version: nil)])
    }
}

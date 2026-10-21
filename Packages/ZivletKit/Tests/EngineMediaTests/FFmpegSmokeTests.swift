import Foundation
import Testing
import ZivletCore

@testable import EngineMedia

/// Opt-in: `ZIVLET_FFMPEG_DIR=/path/to/bin make smoke`. Each case synthesizes a tiny input with lavfi, runs the
/// planned argv through that ffmpeg and checks the output with ffprobe. Cases whose encoders or filters the build
/// lacks are reported as known issues, never as silent passes. A failing case keeps its directory for inspection.
@Suite("ffmpeg smoke (opt-in, ZIVLET_FFMPEG_DIR)", .enabled(if: SmokeEnvironment.toolDirectory != nil))
struct FFmpegSmokeTests {
    @Test(arguments: SmokeCases.all)
    func plannedArgvRunsAndProducesTheExpectedStreams(_ smoke: SmokeCase) throws {
        let tools = SmokeTools(directory: try #require(SmokeEnvironment.toolDirectory))
        let missing = Set(smoke.requires).subtracting(try tools.capabilities())
        guard missing.isEmpty else {
            withKnownIssue("ffmpeg build lacks \(missing.sorted())") { Issue.record("\(smoke.name) not run") }
            return
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zivlet-smoke-\(smoke.name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let input = try synthesize(smoke, in: dir, tools: tools)
        let staged = dir.appendingPathComponent("output.\(smoke.target.rawValue)")
        let request = MediaPlanRequest(
            source: input.path, sourceFormat: smoke.source, info: smoke.info, target: smoke.target,
            staged: staged.path, options: smoke.options, capabilities: smoke.caps)
        for pass in try MediaPlanner.plan(request).passes {
            let result = try tools.run(tools.ffmpeg, pass.argv)
            try #require(result.status == 0, "\(smoke.name) exit \(result.status): \(result.stderr)")
        }
        try check(try tools.probe(staged), against: smoke)
        try FileManager.default.removeItem(at: dir)
    }

    private func synthesize(_ smoke: SmokeCase, in dir: URL, tools: SmokeTools) throws -> URL {
        try "1\n00:00:00,000 --> 00:00:00,900\nhello\n".write(
            to: dir.appendingPathComponent("s.srt"), atomically: true, encoding: .utf8)
        let input = dir.appendingPathComponent("input.\(smoke.source.rawValue)")
        let args = smoke.synth.map { $0.replacingOccurrences(of: "{dir}", with: dir.path) }
        let result = try tools.run(tools.ffmpeg, ["-hide_banner", "-loglevel", "error", "-y"] + args + [input.path])
        try #require(result.status == 0, "\(smoke.name) synthesis: \(result.stderr)")
        return input
    }

    private func check(_ streams: [ProbeStream], against smoke: SmokeCase) throws {
        #expect(streams.map(\.summary) == smoke.streams, "\(smoke.name)")
        for (key, expected) in smoke.fields {
            let parts = key.split(separator: ".").map(String.init)
            try #require(parts.count == 2, "bad field key \(key)")
            let actual = streams.first { $0.codecType == parts[0] }?.field(parts[1])
            #expect(actual == expected, "\(smoke.name) \(key)")
        }
    }
}

enum SmokeCases {
    static let video = ["-f", "lavfi", "-i", "testsrc=d=1:s=64x64:r=10"]
    static func tone(_ rate: Int) -> [String] { ["-f", "lavfi", "-i", "sine=d=1:sample_rate=\(rate)"] }
    static let h264 = Fx.video(0, "h264", 64, 64, fps: 10)
    static let aacMono = Fx.audio(1, "aac", rate: 44_100, channels: 1)

    static let all: [SmokeCase] = remux + audio + video2video + gif

    static let remux: [SmokeCase] = [
        SmokeCase(
            "mov-tmcd__mkv",
            synth: video + tone(44_100) + ["-timecode", "00:00:00:00", "-c:v", "libx264", "-c:a", "aac"],
            .mov, .mkv, Fx.info(h264, aacMono, Fx.data(2, "tmcd")), streams: ["video:h264", "audio:aac"],
            requires: ["libx264"]),
        SmokeCase(
            "mp4-movtext__mkv",
            synth: video + tone(44_100) + ["-i", "{dir}/s.srt", "-map", "0", "-map", "1", "-map", "2"]
                + ["-c:v", "libx264", "-c:a", "aac", "-c:s", "mov_text"],
            .mp4, .mkv, Fx.info(h264, aacMono, Fx.subtitle(2, "mov_text")),
            streams: ["video:h264", "audio:aac", "subtitle:subrip"], requires: ["libx264", "mov_text", "srt"]),
    ]

    static let audio: [SmokeCase] = [
        SmokeCase(
            "mp3__wav", synth: tone(44_100) + ["-c:a", "libmp3lame"], .mp3, .wav,
            Fx.info(Fx.audio(0, "mp3", rate: 44_100, channels: 1)), streams: ["audio:pcm_s16le"],
            requires: ["libmp3lame"]),
        SmokeCase(
            "mp3__flac", synth: tone(44_100) + ["-c:a", "libmp3lame"], .mp3, .flac,
            Fx.info(Fx.audio(0, "mp3", rate: 44_100, channels: 1)), streams: ["audio:flac"],
            fields: ["audio.sample_fmt": "s16"], requires: ["libmp3lame", "flac"]),
        SmokeCase(
            "m4a-aac__aiff", synth: tone(44_100) + ["-c:a", "aac"], .m4a, .aiff,
            Fx.info(Fx.audio(0, "aac", rate: 44_100, channels: 1)), streams: ["audio:pcm_s16be"], requires: []),
        SmokeCase(
            "opus-51__wma",
            synth: tone(48_000) + ["-af", "pan=5.1|c0=c0|c1=c0|c2=c0|c3=c0|c4=c0|c5=c0"]
                + ["-c:a", "libopus", "-mapping_family", "1"],
            .opus, .wma, Fx.info(Fx.audio(0, "opus", rate: 48_000, channels: 6)), streams: ["audio:wmav2"],
            fields: ["audio.channels": "2"], requires: ["libopus", "wmav2"]),
        SmokeCase(
            "m4a-aac__ogg", synth: tone(44_100) + ["-c:a", "aac"], .m4a, .ogg,
            Fx.info(Fx.audio(0, "aac", rate: 44_100, channels: 1)), streams: ["audio:vorbis"],
            requires: ["libvorbis"]),
    ]

    static let video2video: [SmokeCase] = [
        SmokeCase(
            "mov-96k__wmv", synth: video + tone(96_000) + ["-c:v", "libx264", "-c:a", "pcm_s24le"], .mov, .wmv,
            Fx.info(h264, Fx.audio(1, "pcm_s24le", rate: 96_000, channels: 1, bits: 24, sampleFmt: "s32")),
            streams: ["video:wmv2", "audio:wmav2"], fields: ["audio.sample_rate": "48000", "audio.channels": "2"],
            requires: ["libx264", "wmv2", "wmav2"]),
        SmokeCase(
            "webm-vp9alpha__mov",
            synth: ["-f", "lavfi", "-i", "testsrc=d=1:s=64x64:r=10,format=yuva420p"] + tone(48_000)
                + ["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-c:a", "libopus"],
            .webm, .mov,
            Fx.info(Fx.video(0, "vp9", 64, 64, fps: 10, pixFmt: "yuva420p"), Fx.audio(1, "opus", channels: 1)),
            streams: ["video:hevc", "audio:aac"], requires: ["libvpx-vp9", "libopus", "hevc_videotoolbox", "aac_at"]),
        SmokeCase(
            "mov-1080p__mp4-720", synth: ["-f", "lavfi", "-i", "testsrc=d=0.5:s=1920x1080:r=10", "-c:v", "libx264"],
            .mov, .mp4, Fx.info(Fx.video(0, "h264", 1920, 1080, fps: 10)), options: MediaOptions(heightLimit: 720),
            streams: ["video:h264"], fields: ["video.height": "720"], requires: ["libx264", "h264_videotoolbox"]),
        SmokeCase(
            "webm-vp9__mp4-x264", synth: video + tone(48_000) + ["-c:v", "libvpx-vp9", "-c:a", "libopus"], .webm, .mp4,
            Fx.info(Fx.video(0, "vp9", 64, 64, fps: 10), Fx.audio(1, "opus", channels: 1)),
            caps: MediaCapabilities(videoToolbox: false), streams: ["video:h264", "audio:aac"],
            requires: ["libvpx-vp9", "libopus", "libx264", "aac_at"]),
        SmokeCase(
            "mp4__avi", synth: video + tone(44_100) + ["-c:v", "libx264", "-c:a", "aac"], .mp4, .avi,
            Fx.info(h264, aacMono), streams: ["video:mpeg4", "audio:mp3"], requires: ["libx264", "libmp3lame"]),
        SmokeCase(
            "mov-hdr__webm",
            synth: video + ["-c:v", "libx265", "-pix_fmt", "yuv420p10le", "-color_trc", "smpte2084"]
                + ["-color_primaries", "bt2020", "-colorspace", "bt2020nc"],
            .mov, .webm, Fx.info(Fx.video(0, "hevc", 64, 64, fps: 10, pixFmt: "yuv420p10le", hdr: true)),
            streams: ["video:vp9"], requires: ["libx265", "zscale", "tonemap", "libvpx-vp9"]),
    ]

    static let gif: [SmokeCase] = [
        SmokeCase(
            "mov__gif", synth: video + ["-c:v", "libx264"], .mov, .gif, Fx.info(h264), streams: ["video:gif"],
            requires: ["libx264", "gif", "palettegen", "paletteuse"]),
        SmokeCase(
            "gif__mp4", synth: video + ["-c:v", "gif"], .gif, .mp4,
            Fx.info(Fx.video(0, "gif", 64, 64, fps: 10, pixFmt: "bgra")), streams: ["video:h264"],
            requires: ["gif", "h264_videotoolbox"]),
    ]
}

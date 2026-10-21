import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

@Suite("Media planner goldens (P1-02/P1-05 early, 03b §5.4–5.7)")
struct MediaGoldenTests {
    static let cases: [(String, MediaPlanRequest, Lane)] = [
        ("mp4-h264-aac__mov", Fx.request(.mp4, .mov, Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac"))), .remux),
        ("mkv-h264-opus__mp4", Fx.request(.mkv, .mp4, Fx.info(Fx.video(0, "h264"), Fx.audio(1, "opus"))), .audio),
        ("wav-s24__mp3", Fx.request(.wav, .mp3, Fx.info(Fx.audio(0, "pcm_s24le", bits: 24, sampleFmt: "s32"))), .audio),
        (
            "flac-96k-cover__m4a",
            Fx.request(
                .flac, .m4a,
                Fx.info(
                    Fx.audio(
                        0, "flac", rate: 96_000, bits: 24,
                        sampleFmt: "s32"), Fx.cover(1))), .audio
        ),
        ("mp3__opus", Fx.request(.mp3, .opus, Fx.info(Fx.audio(0, "mp3", rate: 44_100))), .audio),
        ("m4a-aac__ogg", Fx.request(.m4a, .ogg, Fx.info(Fx.audio(0, "aac"))), .audio),
        // Lossy decoders report sample_fmt fltp; that is not a float source (unknown depth -> 16-bit).
        ("mp3__wav", Fx.request(.mp3, .wav, Fx.info(Fx.audio(0, "mp3", rate: 44_100))), .audio),
        ("mp3__flac", Fx.request(.mp3, .flac, Fx.info(Fx.audio(0, "mp3", rate: 44_100))), .audio),
        ("m4a-aac__aiff", Fx.request(.m4a, .aiff, Fx.info(Fx.audio(0, "aac"))), .audio),
        ("wav-f32__flac", Fx.request(.wav, .flac, Fx.info(Fx.audio(0, "pcm_f32le", sampleFmt: "flt"))), .audio),
        ("ogg-51__wma", Fx.request(.ogg, .wma, Fx.info(Fx.audio(0, "vorbis", channels: 6))), .audio),
        (
            "aiff-s16__wav", Fx.request(.aiff, .wav, Fx.info(Fx.audio(0, "pcm_s16be", bits: 16, sampleFmt: "s16"))),
            .audio
        ),
        ("mp4-mp3audio__mp3", Fx.request(.mp4, .mp3, Fx.info(Fx.video(0, "h264"), Fx.audio(1, "mp3"))), .remux),
        (
            "mov-hevc10-hdr__webm",
            Fx.request(
                .mov, .webm,
                Fx.info(
                    Fx.video(
                        0, "hevc", 3840, 2160, pixFmt: "yuv420p10le",
                        hdr: true), Fx.audio(1, "aac"))), .swVideo
        ),
        (
            "avi-mpeg4-bframes__mp4",
            Fx.request(
                .avi, .mp4,
                Fx.info(
                    Fx.video(0, "mpeg4", 640, 360, bFrames: 2),
                    Fx.audio(1, "mp3"))), .hwVideo
        ),
        (
            "webm-vp9alpha__mov",
            Fx.request(.webm, .mov, Fx.info(Fx.video(0, "vp9", 1280, 720, pixFmt: "yuva420p"), Fx.audio(1, "opus"))),
            .hwVideo
        ),
        ("mp4-odd__wmv", Fx.request(.mp4, .wmv, Fx.info(Fx.video(0, "h264", 853, 480), Fx.audio(1, "aac"))), .swVideo),
        ("mov__mkv", Fx.request(.mov, .mkv, Fx.info(Fx.video(0, "prores"), Fx.audio(1, "pcm_s24le"))), .remux),
        (
            "mov-tmcd__mkv",
            Fx.request(.mov, .mkv, Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac"), Fx.data(2, "tmcd"))), .remux
        ),
        (
            "mp4-movtext__mkv",
            Fx.request(.mp4, .mkv, Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac"), Fx.subtitle(2, "mov_text"))),
            .remux
        ),
        ("mov-30fps__gif", Fx.request(.mov, .gif, Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac"))), .swVideo),
        (
            "gif-odd__mp4", Fx.request(.gif, .mp4, Fx.info(Fx.video(0, "gif", 301, 200, fps: 12.5, pixFmt: "bgra"))),
            .hwVideo
        ),
        (
            "gif__mov", Fx.request(.gif, .mov, Fx.info(Fx.video(0, "gif", 300, 200, fps: 12.5, pixFmt: "bgra"))),
            .hwVideo
        ),
        (
            "gif__avi", Fx.request(.gif, .avi, Fx.info(Fx.video(0, "gif", 300, 200, fps: 12.5, pixFmt: "bgra"))),
            .swVideo
        ),
    ]

    @Test(arguments: cases)
    func argvMatchesGolden(name: String, request: MediaPlanRequest, lane: Lane) throws {
        let plan = try MediaPlanner.plan(request)
        let prefix = FFmpegArgs.prefix(demuxer: FFmpegArgs.demuxer(for: request.sourceFormat), source: request.source)
        #expect(plan.passes.count == 1)
        #expect(Array(plan.passes[0].argv.prefix(prefix.count)) == prefix)
        #expect(Array(plan.passes[0].argv.dropFirst(prefix.count)) == (try Golden.tail(name)), "\(name)")
        #expect(plan.lane == lane)
        #expect(plan.passes.map(\.weight) == [1])
        #expect(plan.expectedDurationMicros == 10_000_000)
    }

    @Test func prefixIsFixed() {
        #expect(
            FFmpegArgs.prefix(demuxer: "mov", source: "/in/x.mp4") == [
                "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats",
                "-protocol_whitelist", "file,pipe", "-f", "mov", "-i", "file:/in/x.mp4",
            ])
    }
}

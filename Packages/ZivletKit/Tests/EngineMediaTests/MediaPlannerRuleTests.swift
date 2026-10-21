import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

@Suite("Media planner rules (03b §5.2–5.6)")
struct MediaPlannerRuleTests {
    func argv(_ r: MediaPlanRequest) throws -> [String] { try MediaPlanner.plan(r).passes[0].argv }

    @Test(arguments: [
        (FormatID.mp4, "mov"), (.mov, "mov"), (.m4a, "mov"), (.mkv, "matroska"), (.webm, "matroska"), (.avi, "avi"),
        (.wmv, "asf"), (.wma, "asf"), (.ogg, "ogg"), (.opus, "ogg"), (.mp3, "mp3"), (.wav, "wav"), (.flac, "flac"),
        (.aiff, "aiff"), (.gif, "gif"),
    ])
    func demuxerIsForcedFromTheSourceFormat(format: FormatID, demuxer: String) {
        #expect(FFmpegArgs.demuxer(for: format) == demuxer)
    }

    @Test(arguments: [
        (FormatID.mp3, QualityTier.small, ["-q:a", "4"]), (.mp3, .best, ["-q:a", "0"]),
        (.m4a, .small, ["-b:a", "128k"]), (.m4a, .best, ["-b:a", "256k"]),
        (.ogg, .small, ["-q:a", "3"]), (.ogg, .best, ["-q:a", "8"]),
        (.opus, .small, ["-b:a", "96k"]), (.opus, .best, ["-b:a", "192k"]),
        (.flac, .small, ["-compression_level", "3"]), (.flac, .best, ["-compression_level", "12"]),
        (.wma, .best, ["-b:a", "192k"]),
    ])
    func qualityLadders(target: FormatID, tier: QualityTier, expected: [String]) throws {
        let options = MediaOptions(tier: tier)
        let source: FormatID = target == .wav ? .flac : .wav
        let args = try argv(
            Fx.request(
                source, target, Fx.info(Fx.audio(0, "pcm_s16le", bits: 16, sampleFmt: "s16")),
                options: options))
        #expect(args.contains(subsequence: expected), "\(target) \(tier): \(args)")
    }

    static func videoFilter(_ argv: [String]) throws -> String {
        try #require(argv.firstIndex(of: "-vf").map { argv[$0 + 1] })
    }

    @Test func toneMapChainNamesTheInputTransferMatrixAndPrimaries() throws {
        let info = Fx.info(
            Fx.video(
                0, "hevc", 3840, 2160, pixFmt: "yuv420p10le", transfer: "arib-std-b67", primaries: "bt2020",
                matrix: "bt2020nc"))
        let vf = try Self.videoFilter(argv(Fx.request(.mov, .webm, info)))
        #expect(vf.hasPrefix("zscale=tin=arib-std-b67:min=bt2020nc:pin=bt2020:t=linear:npl=100:p=bt2020,"))
        #expect(vf.hasSuffix(",zscale=t=bt709:m=bt709:r=tv,format=yuv420p"))
    }

    /// HEVC Main 10 keeps HDR (no tone-map), so these use VP9 WebM, which is 8-bit SDR.
    /// A stream whose probe says PQ but whose container names no matrix or primaries: BT.2020 is assumed, so zscale
    /// is never left to guess ("no path between colorspaces").
    @Test func untaggedHDRAssumesBT2020() throws {
        let info = Fx.info(Fx.video(0, "hevc", 64, 64, pixFmt: "yuv420p10le", hdr: true))
        let vf = try Self.videoFilter(argv(Fx.request(.mov, .webm, info)))
        #expect(vf.hasPrefix("zscale=tin=smpte2084:min=bt2020nc:pin=bt2020:t=linear"))
    }

    @Test(arguments: ["bt2020nc:t=linear,drawtext=x", "", "unknown"])
    func unexpectedProbeNamesNeverReachTheFilterGraph(name: String) throws {
        let info = Fx.info(
            Fx.video(0, "hevc", 64, 64, pixFmt: "yuv420p10le", hdr: true, primaries: name, matrix: name))
        let vf = try Self.videoFilter(argv(Fx.request(.mov, .webm, info)))
        #expect(vf.hasPrefix("zscale=tin=smpte2084:min=bt2020nc:pin=bt2020:t=linear"))
        #expect(!vf.contains("drawtext"))
    }

    @Test func gifToneMapNamesTheInputToo() throws {
        let info = Fx.info(Fx.video(0, "hevc", 64, 64, pixFmt: "yuv420p10le", transfer: "arib-std-b67"))
        let args = try argv(Fx.request(.mov, .gif, info))
        let graph = try #require(args.firstIndex(of: "-filter_complex"))
        #expect(args[graph + 1].hasPrefix("[0:0]zscale=tin=arib-std-b67:min=bt2020nc:pin=bt2020:"))
    }

    @Test func movDefaultsToHighEverythingElseToBalanced() {
        #expect(MediaOptions.defaults(for: .mov).tier == .best)
        #expect(MediaOptions.defaults(for: .mp4).tier == .standard)
    }

    @Test func metadataOffDropsTagsChaptersAndCover() throws {
        let options = MediaOptions(keepMetadata: false)
        let args = try argv(Fx.request(.flac, .mp3, Fx.info(Fx.audio(0, "flac"), Fx.cover(1)), options: options))
        #expect(args.contains(subsequence: ["-map_metadata", "-1", "-map_chapters", "-1"]))
        #expect(!args.contains("attached_pic") && args.contains("-vn"))
    }

    @Test func videoToolboxMissingFallsBackToX264() throws {
        let caps = MediaCapabilities(videoToolbox: false)
        let args = try argv(Fx.request(.webm, .mp4, Fx.info(Fx.video(0, "vp9"), Fx.audio(1, "opus")), caps: caps))
        #expect(args.contains(subsequence: ["-c:v", "libx264", "-preset", "medium", "-crf", "23"]))
        #expect(
            try MediaPlanner.plan(Fx.request(.webm, .mp4, Fx.info(Fx.video(0, "vp9")), caps: caps)).lane == .swVideo)
    }

    @Test func hevcCopyGetsHvc1TagAndTenBitReencodeUsesMain10() throws {
        #expect(
            try argv(Fx.request(.mkv, .mp4, Fx.info(Fx.video(0, "hevc")))).contains(subsequence: [
                "-c:v", "copy", "-tag:v", "hvc1",
            ]))
        let tenBit = Fx.info(Fx.video(0, "vp9", pixFmt: "yuv420p10le"))
        #expect(
            try argv(Fx.request(.webm, .mov, tenBit)).contains(subsequence: [
                "-profile:v", "main10", "-pix_fmt", "p010le",
            ]))
    }

    @Test func av1CopiesIntoMP4OnlyWithHardwareDecodeAndCompatibilityOff() throws {
        let av1 = Fx.info(Fx.video(0, "av1"))
        #expect(try !argv(Fx.request(.webm, .mp4, av1)).contains(subsequence: ["-c:v", "copy"]))
        let caps = MediaCapabilities(av1HardwareDecode: true)
        let options = MediaOptions(maximumCompatibility: false)
        #expect(
            try argv(Fx.request(.webm, .mp4, av1, options: options, caps: caps)).contains(subsequence: ["-c:v", "copy"])
        )
    }

    @Test func maxHeightScalesOnlyTallerSources() throws {
        let options = MediaOptions(heightLimit: 720)
        #expect(
            try argv(Fx.request(.webm, .mp4, Fx.info(Fx.video(0, "vp9")), options: options))
                .contains(subsequence: ["-vf", "scale=-2:720"]))
        #expect(
            try !argv(Fx.request(.webm, .mp4, Fx.info(Fx.video(0, "vp9", 640, 360)), options: options)).contains("-vf"))
    }

    @Test func textSubtitlesAreConvertedImageSubtitlesDropped() throws {
        let srt = StreamInfo(index: 2, kind: .subtitle, codec: "subrip", isDefault: true)
        let pgs = StreamInfo(index: 3, kind: .subtitle, codec: "hdmv_pgs_subtitle")
        let args = try argv(
            Fx.request(
                .mkv, .mp4,
                MediaInfo(
                    formatName: "matroska", durationMicros: nil,
                    streams: [Fx.video(0, "h264"), Fx.audio(1, "aac"), srt, pgs])))
        #expect(args.contains(subsequence: ["-map", "0:2"]) && !args.contains("0:3"))
        #expect(args.contains(subsequence: ["-c:s", "mov_text"]))
    }

    @Test func matroskaRemuxKeepsWhatMatroskaStoresAndConvertsTimedText() throws {
        let info = Fx.info(
            Fx.video(0, "hevc"), Fx.audio(1, "aac"), Fx.data(2, "tmcd"), Fx.subtitle(3, "hdmv_pgs_subtitle"),
            Fx.subtitle(4, "eia_608"), Fx.subtitle(5, "text"), Fx.cover(6),
            StreamInfo(index: 7, kind: .attachment, codec: "ttf"), Fx.subtitle(8, "mov_text"))
        let args = try argv(Fx.request(.mov, .mkv, info))
        let maps = ["0:0", "0:1", "0:3", "0:5", "0:6", "0:7", "0:8"].flatMap { ["-map", $0] }
        #expect(args.contains(subsequence: maps + ["-c", "copy", "-c:s:1", "srt", "-c:s:2", "srt"]))
        #expect(!args.contains("0:2") && !args.contains("0:4"))
    }

    @Test(arguments: ["aac", "wmav2"])
    func wmvAudioAbove48kHzIsResampled(codec: String) throws {
        let hiRes = Fx.info(Fx.video(0, "h264"), Fx.audio(1, codec, rate: 96_000))
        let args = try argv(Fx.request(.mp4, .wmv, hiRes))
        #expect(args.contains(subsequence: ["-c:a", "wmav2", "-b:a", "192k", "-ac", "2", "-ar", "48000"]))
        let cd = Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac", rate: 44_100))
        #expect(try !argv(Fx.request(.mp4, .wmv, cd)).contains("-ar"))
    }

    @Test func severalAudioTracksGetPerStreamCodecs() throws {
        let info = Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac"), Fx.audio(2, "flac", isDefault: false))
        let args = try argv(Fx.request(.mkv, .mp4, info))
        #expect(args.contains(subsequence: ["-c:a:0", "copy", "-c:a:1", "aac_at", "-b:a", "192k"]))
    }

    @Test func gifOptionsAndFrameRateCap() throws {
        let options = MediaOptions(gifFPS: 24, gifWidthLimit: nil, gifDither: .bayer)
        let graph = try argv(Fx.request(.mp4, .gif, Fx.info(Fx.video(0, "h264", fps: 12)), options: options))
        let filter = try #require(graph.firstIndex(of: "-filter_complex").map { graph[$0 + 1] })
        #expect(filter.hasPrefix("[0:0]fps=12,split[a][b]"))
        #expect(filter.hasSuffix("dither=bayer:diff_mode=rectangle"))
    }

    @Test(arguments: [
        (Fx.request(.mp4, .mp3, Fx.info(Fx.video(0, "h264"))), MediaPlanError.noAudioTrack),
        (Fx.request(.mp4, .gif, Fx.info(Fx.audio(0, "aac"))), .noVideoTrack),
        (Fx.request(.mov, .mp4, Fx.info(Fx.audio(0, "aac"))), .noVideoTrack),
        (
            MediaPlanRequest(
                source: "rel/x.mp4", sourceFormat: .mp4, info: Fx.info(), target: .mov, staged: "/o/y.mov"),
            .invalidPath("rel/x.mp4")
        ),
        (Fx.request(.wav, .mp4, Fx.info(Fx.audio(0, "pcm_s16le"))), .pairNotSupported(.wav, .mp4)),
    ])
    func refusals(request: MediaPlanRequest, error: MediaPlanError) {
        #expect(throws: error) { try MediaPlanner.plan(request) }
    }

    @Test func invalidOptionsAreRejectedAtTheBoundary() {
        let options = MediaOptions(gifFPS: 12)
        #expect(throws: MediaPlanError.invalidOption(.gifFPS, 12)) {
            try MediaPlanner.plan(Fx.request(.mp4, .gif, Fx.info(Fx.video(0, "h264")), options: options))
        }
    }

    /// Every audio/video/GIF pair in the catalog (104) plans for a typical source.
    @Test func everyMediaPairInTheCatalogPlans() throws {
        let media: Set<FormatCategory> = [.audio, .video, .gif]
        let pairs = ConversionCatalog.standard.pairs.filter {
            media.contains(FormatRegistry.standard.format($0.source).category)
        }
        #expect(pairs.count == 104)
        for pair in pairs {
            let isAudio = FormatRegistry.standard.format(pair.source).category == .audio
            let info = isAudio ? Fx.info(Fx.audio(0, "pcm_s16le")) : Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac"))
            let plan = try MediaPlanner.plan(Fx.request(pair.source, pair.target, info))
            #expect(plan.passes[0].argv.last == "file:/out/y.\(pair.target.rawValue)")
        }
    }
}

extension Array where Element == String {
    func contains(subsequence: [String]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else { return subsequence.isEmpty }
        return (0...(count - subsequence.count)).contains { Array(self[$0..<($0 + subsequence.count)]) == subsequence }
    }
}

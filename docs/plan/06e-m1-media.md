# 06e — M1 task 8: EngineMedia argv planners

Part of [06-implementation-plan-m1](06-implementation-plan-m1.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 8 — EngineMedia argv planners (audio, video, GIF)

| Field | Value |
|---|---|
| Goal | Pure planners: `(MediaInfo, target, options, capabilities) → FFmpegPlan` for all 104 media pairs (56 audio, 42 video, 6 GIF), checked by whole-argv goldens |
| 05 rows | Planner part of P1-04, P1-05, P1-06, pulled into M1 (ffprobe JSON parsing P1-02, execution P1-23 stay in Phase 1) |
| Sources | 03b §5.1 (probe model, derived predicates), 03b §5.2 (canonical argv, demuxer map, filter order), 03b §5.3 (copy sets), 03b §5.4 (audio table), 03b §5.5 (video table), 03b §5.6 (GIF), 03b §5.7 (golden examples), 11 §9–§10 (defaults) |

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| replace placeholder | `Sources/ZivletEngineKit/Lane.swift`, `Tests/ZivletEngineKitTests/LaneTests.swift` |
| create | `Sources/EngineMedia/MediaInfo.swift` — `MediaInfo`, `StreamInfo`, `StreamKind` |
| create | `Sources/EngineMedia/MediaOptions.swift` — `QualityTier`, `GIFDither`, `MediaOptions`, `MediaCapabilities` |
| create | `Sources/EngineMedia/FFmpegPlan.swift` — `FFmpegPlan`, `MediaPlanError`, `MediaPlanRequest` |
| create | `Sources/EngineMedia/FFmpegArgs.swift`, `MediaPlanner.swift` |
| create | `Sources/EngineMedia/AudioEncoders.swift`, `AudioPlanner.swift` |
| create | `Sources/EngineMedia/VideoEncoders.swift`, `VideoAudioRules.swift`, `VideoPlanner.swift`, `GIFPlanner.swift` |
| create | `Tests/EngineMediaTests/MediaFixtures.swift`, `MediaGoldenTests.swift`, `MediaPlannerRuleTests.swift`, `Goldens/*.txt` (18) |
| edit | `Package.swift`: `EngineMediaTests` gets `resources: [.copy("Goldens")]` |
| delete | EngineMedia and EngineKit placeholders and smoke tests |

### 8.1 Failing tests first

`Lane` first (EngineKit holds only this in M1, index D9):

```swift
import Testing

@testable import ZivletEngineKit

@Test func elevenLanesWithStableRawValues() {
    #expect(Lane.allCases.count == 11)
    #expect(Lane.hwVideo.rawValue == "hwVideo")
}
```

Fixtures and the golden loader. A golden is the argv **after** the fixed 14-element prefix, on one line, split on spaces
(test paths contain no spaces); the prefix has its own literal test.

```swift
import Foundation
import ZivletCore

@testable import EngineMedia

/// Probe values shaped like ffprobe output. Built per test; never mutated after construction.
enum Fx {
    static func video(
        _ index: Int, _ codec: String, _ w: Int = 1920, _ h: Int = 1080, fps: Double = 30,
        pixFmt: String = "yuv420p", hdr: Bool = false, bFrames: Int = 0
    ) -> StreamInfo {
        StreamInfo(
            index: index, kind: .video, codec: codec, width: w, height: h, pixFmt: pixFmt, hasBFrames: bFrames,
            colorTransfer: hdr ? "smpte2084" : "bt709", avgFrameRate: fps)
    }

    static func audio(
        _ index: Int, _ codec: String, rate: Int = 48_000, channels: Int = 2, bits: Int? = nil,
        sampleFmt: String = "fltp", isDefault: Bool = true
    ) -> StreamInfo {
        StreamInfo(
            index: index, kind: .audio, codec: codec, bitsPerRawSample: bits, sampleRate: rate, channels: channels,
            sampleFmt: sampleFmt, isDefault: isDefault)
    }

    static func cover(_ index: Int) -> StreamInfo {
        StreamInfo(index: index, kind: .video, codec: "mjpeg", isAttachedPic: true)
    }

    static func info(_ streams: StreamInfo...) -> MediaInfo {
        MediaInfo(formatName: "test", durationMicros: 10_000_000, streams: streams)
    }

    static func request(
        _ from: FormatID, _ to: FormatID, _ info: MediaInfo,
        options: MediaOptions? = nil, caps: MediaCapabilities = MediaCapabilities()
    ) -> MediaPlanRequest {
        MediaPlanRequest(
            source: "/in/x.\(from.rawValue)", sourceFormat: from, info: info, target: to,
            staged: "/out/y.\(to.rawValue)", options: options, capabilities: caps)
    }
}

enum Golden {
    struct Missing: Error { let name: String }

    /// Golden = argv after the fixed prefix, one line, space-separated (test paths contain no spaces).
    static func tail(_ name: String) throws -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Goldens") else {
            throw Missing(name: name)
        }
        let line = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return line.split(separator: " ").map(String.init)
    }
}
```

Golden files. The first three are 03b §5.7 verbatim; the others apply the 03b §5.4–5.6 tables by hand.

```bash
mkdir -p Tests/EngineMediaTests/Goldens && cd Tests/EngineMediaTests/Goldens
cat > aiff-s16__wav.txt <<'EOF'
-map 0:0 -vn -sn -dn -c:a pcm_s16le -map_metadata 0 -map_chapters 0 -rf64 auto -f wav file:/out/y.wav
EOF
cat > avi-mpeg4-bframes__mp4.txt <<'EOF'
-map 0:0 -map 0:1 -c:v h264_videotoolbox -profile:v high -allow_sw 1 -pix_fmt yuv420p -tag:v avc1 -q:v 60 -c:a copy -map_metadata 0 -map_chapters 0 -movflags +faststart -f mp4 file:/out/y.mp4
EOF
cat > flac-96k-cover__m4a.txt <<'EOF'
-map 0:0 -map 0:1 -c:v copy -disposition:v:0 attached_pic -sn -dn -c:a aac_at -b:a 192k -ar 48000 -map_metadata 0 -map_chapters 0 -movflags +faststart -f ipod file:/out/y.m4a
EOF
cat > gif-odd__mp4.txt <<'EOF'
-filter_complex color=white:s=301x200[bg];[bg][0:0]overlay=shortest=1,scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p[v] -map [v] -c:v h264_videotoolbox -profile:v high -allow_sw 1 -pix_fmt yuv420p -tag:v avc1 -q:v 60 -fps_mode vfr -map_metadata 0 -map_chapters 0 -movflags +faststart -f mp4 file:/out/y.mp4
EOF
cat > gif__avi.txt <<'EOF'
-filter_complex color=white:s=300x200[bg];[bg][0:0]overlay=shortest=1,format=yuv420p[v] -map [v] -c:v mpeg4 -vtag xvid -fps_mode cfr -q:v 3 -r 13 -map_metadata 0 -map_chapters 0 -f avi file:/out/y.avi
EOF
cat > gif__mov.txt <<'EOF'
-map 0:0 -c:v hevc_videotoolbox -pix_fmt bgra -alpha_quality 0.75 -tag:v hvc1 -q:v 72 -fps_mode vfr -map_metadata 0 -map_chapters 0 -movflags +faststart -f mov file:/out/y.mov
EOF
cat > m4a-aac__ogg.txt <<'EOF'
-map 0:0 -vn -sn -dn -c:a libvorbis -q:a 6 -map_metadata 0 -map_chapters 0 -f ogg file:/out/y.ogg
EOF
cat > mkv-h264-opus__mp4.txt <<'EOF'
-map 0:0 -map 0:1 -c:v copy -c:a aac_at -b:a 192k -map_metadata 0 -map_chapters 0 -movflags +faststart -f mp4 file:/out/y.mp4
EOF
cat > mov-30fps__gif.txt <<'EOF'
-filter_complex [0:0]fps=15,scale='min(480,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff:max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle -an -loop 0 -f gif file:/out/y.gif
EOF
cat > mov-hevc10-hdr__webm.txt <<'EOF'
-map 0:0 -map 0:1 -c:v libvpx-vp9 -b:v 0 -row-mt 1 -tile-columns 2 -deadline good -cpu-used 5 -pix_fmt yuv420p -crf 32 -vf zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p -c:a libopus -b:a 128k -ar 48000 -map_metadata 0 -map_chapters 0 -f webm file:/out/y.webm
EOF
cat > mov__mkv.txt <<'EOF'
-map 0 -c copy -map_metadata 0 -map_chapters 0 -f matroska file:/out/y.mkv
EOF
cat > mp3__opus.txt <<'EOF'
-map 0:0 -vn -sn -dn -c:a libopus -b:a 128k -vbr on -application audio -ar 48000 -map_metadata 0 -map_chapters 0 -f opus file:/out/y.opus
EOF
cat > mp4-h264-aac__mov.txt <<'EOF'
-map 0:0 -map 0:1 -c:v copy -c:a copy -map_metadata 0 -map_chapters 0 -movflags +faststart -f mov file:/out/y.mov
EOF
cat > mp4-mp3audio__mp3.txt <<'EOF'
-map 0:1 -vn -sn -dn -c:a copy -map_metadata 0 -map_chapters 0 -id3v2_version 3 -write_xing 1 -f mp3 file:/out/y.mp3
EOF
cat > mp4-odd__wmv.txt <<'EOF'
-map 0:0 -map 0:1 -c:v wmv2 -fps_mode cfr -q:v 3 -vf scale=trunc(iw/2)*2:trunc(ih/2)*2 -c:a wmav2 -b:a 192k -ac 2 -map_metadata 0 -map_chapters 0 -f asf file:/out/y.wmv
EOF
cat > ogg-51__wma.txt <<'EOF'
-map 0:0 -vn -sn -dn -c:a wmav2 -b:a 192k -ac 2 -map_metadata 0 -map_chapters 0 -f asf file:/out/y.wma
EOF
cat > wav-f32__flac.txt <<'EOF'
-map 0:0 -vn -sn -dn -c:a flac -compression_level 8 -sample_fmt s32 -bits_per_raw_sample 24 -map_metadata 0 -map_chapters 0 -f flac file:/out/y.flac
EOF
cat > wav-s24__mp3.txt <<'EOF'
-map 0:0 -vn -sn -dn -c:a libmp3lame -q:a 2 -map_metadata 0 -map_chapters 0 -id3v2_version 3 -write_xing 1 -f mp3 file:/out/y.mp3
EOF
cd ../../..
```

Then change the `EngineMediaTests` line in `Package.swift`:

```swift
        .testTarget(
            name: "EngineMediaTests", dependencies: ["EngineMedia"], resources: [.copy("Goldens")],
            swiftSettings: strict),
```

```swift
import ZivletCore
import ZivletEngineKit
import Testing

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
        ("mp4-odd__wmv", Fx.request(.mp4, .wmv, Fx.info(Fx.video(0, "h264", 853, 480), Fx.audio(1, "aac"))), .swVideo),
        ("mov__mkv", Fx.request(.mov, .mkv, Fx.info(Fx.video(0, "prores"), Fx.audio(1, "pcm_s24le"))), .remux),
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
        #expect(Array(plan.passes[0].prefix(prefix.count)) == prefix)
        #expect(Array(plan.passes[0].dropFirst(prefix.count)) == (try Golden.tail(name)), "\(name)")
        #expect(plan.lane == lane)
        #expect(plan.passes.map(\.weight) == [1])  // [review] FFmpegPass
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
```

```swift
import ZivletCore
import ZivletEngineKit
import Testing

@testable import EngineMedia

@Suite("Media planner rules (03b §5.2–5.6)")
struct MediaPlannerRuleTests {
    func argv(_ r: MediaPlanRequest) throws -> [String] { try MediaPlanner.plan(r).passes[0] }

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
            #expect(plan.passes[0].last == "file:/out/y.\(pair.target.rawValue)")
        }
    }
}

extension Array where Element == String {
    func contains(subsequence: [String]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else { return subsequence.isEmpty }
        return (0...(count - subsequence.count)).contains { Array(self[$0..<($0 + subsequence.count)]) == subsequence }
    }
}
```

### 8.2 Run, expect failure

`swift test --filter "EngineMediaTests|ZivletEngineKitTests"` → `error: cannot find 'Lane' in scope`. The build stops at
the first failing target; once `Lane.swift` exists the EngineMedia tests fail with `cannot find 'MediaPlanner' in scope`
(and `StreamInfo`, `MediaInfo`, `MediaOptions`, `FFmpegArgs`).

### 8.3 Implement

`Lane.swift` (complete):

```swift
/// Scheduler lanes (02 §7.3, 03a §4.2). Plans name the lane; the runtime (P1) owns the widths.
public enum Lane: String, CaseIterable, Codable, Sendable {
    case cpu, remux, audio, hwVideo, swVideo, render, js, vision, metadata, office, iwork
}
```

Value types — outlines (all stored properties `let`; every init parameter after the identity fields has a default):

```swift
public struct MediaInfo: Sendable, Codable, Equatable {
    public let formatName: String, durationMicros: Int64?, streams: [StreamInfo]
    public var primaryVideo: StreamInfo? { get }      // first video stream that is not an attached picture
    public var primaryAudio: StreamInfo? { get }      // default-disposition audio, else first audio
    public var audioStreams: [StreamInfo] { get }
    public var cover: StreamInfo? { get }             // attached picture, mapped by index
    public var textSubtitles: [StreamInfo] { get }    // subrip, ass, ssa, webvtt, mov_text, text
}
public enum StreamKind: String, Sendable, Codable { case video, audio, subtitle, attachment, data }
public struct StreamInfo: Sendable, Codable, Equatable {
    public let index: Int, kind: StreamKind, codec: String
    public let width: Int?, height: Int?, pixFmt: String?, bitsPerRawSample: Int?, hasBFrames: Int?
    public let colorTransfer: String?, avgFrameRate: Double?, sampleRate: Int?, channels: Int?, sampleFmt: String?
    public let isAttachedPic: Bool, isDefault: Bool
    public var isHDR: Bool { get }          // colorTransfer ∈ {smpte2084, arib-std-b67}
    public var hasAlpha: Bool { get }       // pix_fmt ∈ {yuva420p, yuva444p, rgba, bgra, argb, abgr, gbrap, ya8}
    public var isFloatAudio: Bool { get }   // sample_fmt ∈ {flt, fltp, dbl, dblp}
    public var bitDepth: Int { get }        // bits_per_raw_sample > 0, else …p10le/p010le → 10, …p12le → 12, else 8
}
public struct MediaOptions: Sendable, Codable, Equatable {
    // quality .standard, keepMetadata true, heightLimit nil, maximumCompatibility true,
    // gifFPS 15, gifWidthLimit 480, gifDither .sierra ("sierra2_4a") | .bayer
    public static func defaults(for target: FormatID) -> MediaOptions  // .best for mov, else .standard
    func validate() throws(MediaPlanError)  // heightLimit ∈ {2160,1080,720}; gifFPS ∈ {10,15,24}; gifWidthLimit ∈ {320,480,640,800}
}
public struct MediaCapabilities: Sendable, Codable, Equatable { public let videoToolbox: Bool /* true */, av1HardwareDecode: Bool /* false */ }
public struct FFmpegPlan: Sendable, Codable, Equatable {
    // [review] Superseded: `passes: [FFmpegPass]` (argv + weight, validated), see FFmpegPlan.swift and 03b §5.2.
    public let passes: [[String]], passWeights: [Double], expectedDurationMicros: Int64?, lane: Lane
}
public enum MediaPlanError: Error, Equatable, Sendable {
    case pairNotSupported(FormatID, FormatID), noAudioTrack, noVideoTrack, invalidPath(String), invalidOption(MediaOption, Int) /* [review] typed; + invalidPass */
}
public struct MediaPlanRequest: Sendable, Equatable {
    public let source: String, sourceFormat: FormatID, info: MediaInfo, target: FormatID, staged: String
    public let options: MediaOptions, capabilities: MediaCapabilities
    public init(source:sourceFormat:info:target:staged:options: MediaOptions? = nil /* → defaults(for: target) */,
                capabilities: MediaCapabilities = MediaCapabilities())
}
```

`FFmpegArgs.swift` (complete; it fixes the canonical order, the demuxer and muxer maps, and boundary validation):

```swift
import ZivletCore

/// Fixed argv pieces in canonical order (03b §5.2).
enum FFmpegArgs {
    static func prefix(demuxer: String, source: String) -> [String] {
        [
            "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats",
            "-protocol_whitelist", "file,pipe", "-f", demuxer, "-i", "file:" + source,
        ]
    }

    static func metadata(preserve: Bool) -> [String] {
        preserve ? ["-map_metadata", "0", "-map_chapters", "0"] : ["-map_metadata", "-1", "-map_chapters", "-1"]
    }

    static func output(muxer: String, staged: String) -> [String] { ["-f", muxer, "file:" + staged] }

    /// Forced demuxer per sniffed source format (10 §8.9 challenge).
    static func demuxer(for format: FormatID) -> String {
        switch format {
        case .mp4, .mov, .m4a: "mov"
        case .mkv, .webm: "matroska"
        case .wmv, .wma: "asf"
        case .ogg, .opus: "ogg"
        default: format.rawValue  // mp3, wav, flac, aiff, avi, gif
        }
    }

    static func muxer(for target: FormatID) -> String {
        switch target {
        case .m4a: "ipod"
        case .mkv: "matroska"
        case .wma, .wmv: "asf"
        default: target.rawValue  // mp3 wav aiff flac ogg opus mp4 mov webm avi gif
        }
    }

    static let evenDimensions = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    static let toneMapToSDR =
        "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,"
        + "zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
}

extension MediaPlanRequest {
    func validated() throws(MediaPlanError) -> MediaPlanRequest {
        for path in [source, staged] where !path.hasPrefix("/") || path.contains("\n") || path.contains("\0") {
            throw .invalidPath(path)
        }
        guard ConversionCatalog.standard.canConvert(sourceFormat, to: target) else {
            throw .pairNotSupported(sourceFormat, target)
        }
        try options.validate()
        return self
    }

    var prefix: [String] { FFmpegArgs.prefix(demuxer: FFmpegArgs.demuxer(for: sourceFormat), source: source) }
}
```

`MediaPlanner.swift` (complete; GIF routes first, then audio targets, then video):

```swift
import ZivletCore

/// Entry point: validates the request, then dispatches by route (03b §5.2).
public enum MediaPlanner {
    public static func plan(_ request: MediaPlanRequest) throws(MediaPlanError) -> FFmpegPlan {
        let request = try request.validated()
        let targetFamily = FormatRegistry.standard.format(request.target).family
        if request.target == .gif { return try GIFPlanner.videoToGIF(request) }
        if request.sourceFormat == .gif { return try GIFPlanner.gifToVideo(request) }
        if targetFamily == .audio { return try AudioPlanner.plan(request) }
        return try VideoPlanner.plan(request)
    }
}
```

`AudioPlanner.swift` (complete; the argv order of 03b §5.2 for audio targets):

```swift
import ZivletCore
import ZivletEngineKit

/// Audio targets from any audio source or the primary audio of a video (03b §5.4).
enum AudioPlanner {
    static func plan(_ r: MediaPlanRequest) throws(MediaPlanError) -> FFmpegPlan {
        guard let audio = r.info.primaryAudio else { throw .noAudioTrack }
        let copy = AudioEncoders.copySet(r.target).contains(audio.codec)
        let cover = r.options.keepMetadata && AudioEncoders.coverTargets.contains(r.target) ? r.info.cover : nil
        let maps = ["-map", "0:\(audio.index)"] + (cover.map { ["-map", "0:\($0.index)"] } ?? [])
        let video = cover == nil ? ["-vn"] : ["-c:v", "copy", "-disposition:v:0", "attached_pic"]
        let audioArgs = copy ? ["-c:a", "copy"] : AudioEncoders.encode(r.target, audio, r.options.tier)
        let argv =
            r.prefix + maps + video + ["-sn", "-dn"] + audioArgs
            + FFmpegArgs.metadata(preserve: r.options.keepMetadata)
            + AudioEncoders.containerArgs(r.target)
            + FFmpegArgs.output(muxer: FFmpegArgs.muxer(for: r.target), staged: r.staged)
        return FFmpegPlan(
            passes: [argv], passWeights: [1], expectedDurationMicros: r.info.durationMicros,
            lane: copy ? .remux : .audio)
    }
}
```

`AudioEncoders.swift` — functions over the 03b §5.4 table:

| Function | Content |
|---|---|
| `copySet(_ target:) -> Set<String>` | mp3 {mp3}; m4a {aac, alac}; wav {pcm_s16le, s24le, s32le, f32le}; aiff {pcm_s16be, s24be, s32be}; flac {flac}; ogg {vorbis}; opus {opus}; wma {wmav2} |
| `encode(_:_:_:) -> [String]` | mp3 `libmp3lame -q:a 4/2/0` (+ `-ar 48000` if > 48 kHz, `-ac 2` if > 2 ch); m4a `aac_at -b:a 128k/192k/256k` (+ `-ar 48000`, `-ac 8` if > 8 ch); wav/aiff PCM by depth; flac `-compression_level 3/8/12` (+ `-sample_fmt s32 -bits_per_raw_sample 24` when > 16-bit or float); ogg `libvorbis -q:a 3/6/8`; opus `libopus -b:a 96k/128k/192k -vbr on -application audio -ar 48000` (+ `-mapping_family 1` if > 2 ch); wma `wmav2 -b:a 128k/192k/192k -ac 2` (+ `-ar 48000`) |
| `pcm(_:endian:)` | float → `pcm_f32le` (wav) / `pcm_s24be` (aiff); else ≤ 16 → s16, ≤ 24 → s24, else s32; unknown depth → 16 |
| `containerArgs(_:)` | mp3 `-id3v2_version 3 -write_xing 1`; m4a `-movflags +faststart`; wav `-rf64 auto`; aiff `-write_id3v2 1` |
| `coverTargets` | {mp3, m4a, flac}; ogg/opus/aiff/wma drop the cover in M1 (index D11) |
| `pick(_:_:_:_:)` | small / standard / best selector, shared with video |

`VideoEncoders.swift`, `VideoAudioRules.swift`, `VideoPlanner.swift`, `GIFPlanner.swift` — rules:

| Piece | Rule |
|---|---|
| Video copy (`copyArgs`) | mp4: h264; hevc + `-tag:v hvc1`; av1 only if `av1HardwareDecode && !maximumCompatibility`; mpeg4 only if `hasBFrames == 0`. mov: h264, hevc (+hvc1), prores, mjpeg, mpeg4 (same B-frame rule). webm: vp8, vp9, av1. avi: mpeg4, mjpeg, h264. wmv: wmv1, wmv2. `nil` = re-encode |
| VideoToolbox (mp4, mov, mkv) | `h264_videotoolbox -profile:v high -allow_sw 1 -pix_fmt yuv420p [-tag:v avc1] -q:v 48/60/72` (no tag in mkv); ≥ 10-bit or HDR into mp4/mov → `hevc_videotoolbox -profile:v main10 -pix_fmt p010le -tag:v hvc1 -q:v Q`; GIF alpha into mov → `hevc_videotoolbox -pix_fmt bgra -alpha_quality 0.75 -tag:v hvc1`. Lane `hwVideo` |
| No VideoToolbox | `libx264 -preset medium -crf 26/23/20 -pix_fmt yuv420p` (index D12). Lane `swVideo` |
| webm / avi / wmv | `libvpx-vp9 -b:v 0 -row-mt 1 -tile-columns 2 -deadline good -cpu-used 5 -pix_fmt yuv420p (yuva420p for alpha) -crf 37/32/27`; `mpeg4 -vtag xvid -fps_mode cfr -q:v 5/3/2`; `wmv2 -fps_mode cfr -q:v 5/3/2`. Lane `swVideo` |
| `-vf` (re-encode only) | tonemap (HDR source, target not HEVC main10) → `scale=-2:H` when taller than `heightLimit`, else `scale=trunc(iw/2)*2:trunc(ih/2)*2` when a dimension is odd |
| Streams mapped | mp4/mov: video + every audio + text subtitles (`-c:s mov_text`); webm: video + primary audio + text subtitles (`-c:s webvtt`); avi/wmv: video + primary audio; mkv: `-map 0 -c copy`, lane `remux` |
| Audio in video | copy sets mp4 {aac, alac, mp3, ac3, eac3}; mov {aac, alac, mp3, pcm_*}; webm {opus, vorbis}; avi {mp3, pcm_s16le, ac3} ≤ 2 ch; wmv {wmav2} ≤ 2 ch, ≤ 48 kHz. Re-encode: `aac_at -b:a 192k` (+ `-ac 6` if > 6 ch); `libopus -b:a 128k -ar 48000`; `libmp3lame -b:a 192k -ac 2`; `wmav2 -b:a 192k -ac 2`. One stream → `-c:a`; several → `-c:a:<i>` each |
| Lane | video re-encoded → the encoder's lane; else any audio re-encode → `audio`; else `remux` |
| Video → GIF | `-filter_complex "[0:<v>][tonemap,]fps=F,[scale='min(W,iw)':-2:flags=lanczos,]split[a][b];[a]palettegen=stats_mode=diff:max_colors=256[p];[b][p]paletteuse=dither=<d>:diff_mode=rectangle" -an -loop 0 -f gif`; F = min(option, ⌊source fps⌋); no scale when width is Original. Lane `swVideo` |
| GIF → mp4/mkv/avi/wmv | flatten: `-filter_complex "color=white:s=WxH[bg];[bg][0:<v>]overlay=shortest=1,[even-dims,]format=yuv420p[v]" -map [v]`; then the target encoder; mp4/mkv add `-fps_mode vfr`; avi/wmv add `-r min(round(fps), 50)` |
| GIF → mov/webm | keep alpha: `-map 0:<v>`, HEVC-alpha / VP9 `yuva420p`, `-fps_mode vfr` |

[review] Opt-in execution check: `ZIVLET_FFMPEG_DIR=<dir with ffmpeg, ffprobe> make smoke` runs
`FFmpegSmokeTests` (15 cases: mkv remux with tmcd and mov_text, 96 kHz → wmv, mp3 → wav/flac, aac → aiff, opus 5.1 → wma,
aac → ogg, VP9-alpha → mov, height cap, libx264 fallback, mp4 → avi, HDR tone-map → webm, mov → gif, gif → mp4). Each
case synthesizes its input with lavfi, runs the planned argv and checks ffprobe output. Cases needing an encoder or filter
the build lacks are known issues (Homebrew ffmpeg 8.1.2 has no `libvorbis` and no `zscale`, so the ogg and tone-map cases
wait for the vendored build). `make test` skips the suite. Not every golden is executed: the goldens' hand-written probes
do not correspond to synthesizable files one-to-one.

### 8.4 Verify green

```bash
swift test --filter "EngineMediaTests|ZivletEngineKitTests" 2>&1 | grep -E "Test run with|✘|error:"
```

[critic3] The pattern is `error:` in all M1 verify commands; plain `error` also matched the `error →` argument labels that Swift Testing prints for `refusals(request:error:)`.

Expected: `✔ Test run with 1 test in 0 suites passed` and `✔ Test run with 16 tests in 2 suites passed` (18 goldens,
104-pair sweep included).

### 8.5 Commit

```bash
git add -A Packages/ZivletKit
git commit -s -m "feat(media): add pure audio, video and GIF argv planners with golden tests"
```

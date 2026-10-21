import EngineTestSupport
import Foundation
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

/// Encoder and filter lists shaped like `ffmpeg -encoders` / `-filters`: the Homebrew 8.1.2 build has no libvorbis
/// and no zscale (index D-M3-6).
enum HomebrewLists {
    static let encoders = [
        "libmp3lame", "aac_at", "pcm_s16le", "pcm_s24le", "pcm_f32le", "pcm_s16be", "pcm_s24be", "flac", "libopus",
        "wmav2", "h264_videotoolbox", "hevc_videotoolbox", "libx264", "libvpx-vp9", "mpeg4", "wmv2", "gif", "mov_text",
        "webvtt", "srt",
    ]
    static let filters = ["fps", "scale", "split", "palettegen", "paletteuse", "color", "overlay", "tonemap", "format"]

    static func list(_ names: [String]) -> String {
        "Legend:\n ------\n" + names.map { " V..... \($0)  description" }.joined(separator: "\n") + "\n"
    }

    static let capabilities = FFmpegCapabilities(encoders: Set(encoders), filters: Set(filters))
    static let full = FFmpegCapabilities(encoders: Set(encoders + ["libvorbis"]), filters: Set(filters + ["zscale"]))
}

/// A scripted ffmpeg/ffprobe pair for engine unit tests. `probes` maps a probed file name to its ffprobe JSON; the
/// hidden staged file answers to the key "staged".
struct MediaRig {
    let dir: URL
    let runner: FakeRunner
    let locator: EngineLocator
    let engine: MediaEngine

    static let progress = "out_time_us=500000\nprogress=continue\nout_time_us=1000000\nprogress=end\n"

    init(
        probes: [String: String], ffmpeg: SubprocessResult = FakeRunner.result(MediaRig.progress),
        encoders: [String] = HomebrewLists.encoders, locates: Bool = true, delay: Duration? = nil
    ) throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lists = ["-encoders": HomebrewLists.list(encoders), "-filters": HomebrewLists.list(HomebrewLists.filters)]
        runner = FakeRunner(delay: delay) { request in
            switch request.executable.lastPathComponent {
            case "ffprobe":
                let name = URL(fileURLWithPath: String((request.arguments.last ?? "").dropFirst("file:".count)))
                    .lastPathComponent
                let key = name.hasPrefix(".zivlet-") ? "staged" : name
                return probes[key].map { FakeRunner.result($0) } ?? FakeRunner.result("", status: 1)
            default:
                if let list = lists[request.arguments.last ?? ""] { return FakeRunner.result(list) }
                return ffmpeg
            }
        }
        locator = EngineLocator(
            bundledHelpers: dir, environment: [:], developmentDirectories: [], isExecutable: { _ in locates })
        engine = MediaEngine(locator: locator, runner: runner)
    }

    func input(_ name: String, _ format: FormatID) throws -> InputItem {
        try InputItem(url: dir.appending(path: name), format: format, byteCount: 10)
    }

    func request(_ name: String, _ format: FormatID, to target: FormatID) throws -> JobRequest {
        try JobRequest(input: input(name, format), operation: .convert(target), destination: dir)
    }

    func workspace(_ request: JobRequest) -> JobWorkspace {
        JobWorkspace(
            job: request.id, stagedFile: dir.appending(path: ".zivlet-\(request.id).\(request.target.rawValue)"))
    }

    /// A staged output of `bytes` bytes, as `execute` would leave it.
    func staged(_ request: JobRequest, bytes: Int = 100) throws -> StagedOutput {
        let url = workspace(request).stagedFile
        try Data(repeating: 1, count: bytes).write(to: url)
        return StagedOutput(format: request.target, url: url, byteCount: Int64(bytes))
    }
}

/// Representative probes per source format, for the "every pair plans" sweep.
enum RepresentativeProbe {
    static func info(for format: FormatID) -> MediaInfo {
        switch format {
        case .mp3: Fx.info(Fx.audio(0, "mp3"))
        case .m4a: Fx.info(Fx.audio(0, "aac"))
        case .wav: Fx.info(Fx.audio(0, "pcm_s16le", bits: 16, sampleFmt: "s16"))
        case .flac: Fx.info(Fx.audio(0, "flac", bits: 16, sampleFmt: "s16"))
        case .ogg: Fx.info(Fx.audio(0, "vorbis"))
        case .opus: Fx.info(Fx.audio(0, "opus"))
        case .aiff: Fx.info(Fx.audio(0, "pcm_s16be", bits: 16, sampleFmt: "s16"))
        case .wma: Fx.info(Fx.audio(0, "wmav2"))
        case .webm: Fx.info(Fx.video(0, "vp9"), Fx.audio(1, "opus"))
        case .avi: Fx.info(Fx.video(0, "mpeg4"), Fx.audio(1, "mp3"))
        case .wmv: Fx.info(Fx.video(0, "wmv2"), Fx.audio(1, "wmav2"))
        case .gif: Fx.info(Fx.video(0, "gif", 320, 240, fps: 10, pixFmt: "bgra"))
        default: Fx.info(Fx.video(0, "h264"), Fx.audio(1, "aac"))
        }
    }
}

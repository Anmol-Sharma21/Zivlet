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

    /// An output that ends within this of its `-fs` cap is taken to have hit it (ffmpeg stops before the next packet).
    static let sizeCapSlack: Int64 = 1 << 20

    /// `-fs <bytes>` just before the output (the last argument), so ffmpeg stops writing at `limit`.
    static func capped(_ argv: [String], at limit: Int64?) -> [String] {
        guard let limit, !argv.isEmpty else { return argv }
        return argv.dropLast() + ["-fs", String(limit), argv[argv.count - 1]]
    }

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
    /// HDR → SDR (03b §5.2) with the input signal named, so zscale never has to guess it from container tags. The
    /// first step also names its output primaries: on an untagged frame zscale otherwise copies "unknown" from the
    /// frame and fails with "no path between colorspaces" (seen with the bundled build, D-M4-12).
    static func toneMapToSDR(_ signal: HDRSignal) -> String {
        "zscale=tin=\(signal.transfer):min=\(signal.matrix):pin=\(signal.primaries)"
            + ":t=linear:npl=100:p=\(signal.primaries),"
            + "format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
    }
}

/// The transfer, matrix and primaries of an HDR stream in zscale's names (D-M4-12). Only names on the lists are
/// taken from the probe; anything else (missing, unknown or hostile) becomes BT.2020, which every PQ or HLG stream
/// Zivlet meets uses, so a probe value can never add to the filter graph.
struct HDRSignal: Sendable, Equatable {
    static let transfers: Set<String> = ["smpte2084", "arib-std-b67"]
    static let matrices: Set<String> = ["bt2020nc", "bt2020c", "bt709"]
    static let primarySets: Set<String> = ["bt2020", "smpte432", "bt709"]

    let transfer: String
    let matrix: String
    let primaries: String

    init(_ stream: StreamInfo) {
        transfer = stream.colorTransfer.flatMap { Self.transfers.contains($0) ? $0 : nil } ?? "smpte2084"
        matrix = stream.colorSpace.flatMap { Self.matrices.contains($0) ? $0 : nil } ?? "bt2020nc"
        primaries = stream.colorPrimaries.flatMap { Self.primarySets.contains($0) ? $0 : nil } ?? "bt2020"
    }
}

extension MediaPlanRequest {
    /// Paths: absolute, no Unicode Cc characters (NUL, newline, tab, DEL, C1 included), no ".." component, and the
    /// staged output never spells the same path as the source (the argv carries `-y`).
    func validated(catalog: ConversionCatalog) throws(MediaPlanError) -> MediaPlanRequest {
        for path in [source, staged] where !Self.isSafeAbsolutePath(path) { throw .invalidPath(path) }
        if Self.components(source) == Self.components(staged) { throw .invalidPath(staged) }
        guard catalog.canConvert(sourceFormat, to: target) else {
            throw .pairNotSupported(sourceFormat, target)
        }
        try options.validate()
        return self
    }

    static func isSafeAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains { $0.properties.generalCategory == .control }
            && !path.split(separator: "/").contains("..")
    }

    /// Components without empty and "." entries, so two spellings of one path compare equal.
    static func components(_ path: String) -> [Substring] { path.split(separator: "/").filter { $0 != "." } }

    var prefix: [String] { FFmpegArgs.prefix(demuxer: FFmpegArgs.demuxer(for: sourceFormat), source: source) }
}

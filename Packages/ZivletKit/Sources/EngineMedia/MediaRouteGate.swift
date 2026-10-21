import ZivletCore
import ZivletEngineKit

/// Capability gate for media routes (03a §3.5, P1-11). Two levels: a static table per target (what every plan into
/// that target needs, so the wheel can hide the route before any probe), and the exact encoders and filters a planned
/// argv names (per file: an HDR source needs `zscale` only when it is tone-mapped).
enum MediaRouteGate {
    /// Each inner list is a set of alternatives; the first name is reported when all are missing.
    struct Requirement: Equatable {
        let encoders: [[String]]
        let filters: [String]
    }

    static let h264 = ["h264_videotoolbox", "libx264"]
    static let gifOutputFilters = ["fps", "scale", "split", "palettegen", "paletteuse"]
    static let gifInputFilters = ["color", "overlay"]

    static func availability(
        _ pair: ConversionPair, capabilities: FFmpegCapabilities, registry: FormatRegistry = .standard
    ) -> RouteAvailability {
        let need = requirement(pair, registry: registry)
        let missingEncoders = need.encoders.compactMap { group in
            group.contains(where: capabilities.encoders.contains) ? nil : group.first
        }
        let missing = missingEncoders + capabilities.missing(encoders: [], filters: need.filters)
        return missing.isEmpty ? .available : .unavailable(missing)
    }

    static func requirement(_ pair: ConversionPair, registry: FormatRegistry) -> Requirement {
        let fromGIF = registry.format(pair.source).category == .gif
        let encoders = targetEncoders(pair.target, fromGIF: fromGIF)
        let filters = pair.target == .gif ? gifOutputFilters : fromGIF ? gifInputFilters : []
        return Requirement(encoders: encoders, filters: filters)
    }

    private static func targetEncoders(_ target: FormatID, fromGIF: Bool) -> [[String]] {
        switch target {
        case .mp3: [["libmp3lame"]]
        case .m4a: [["aac_at"]]
        case .wav: [["pcm_s16le"]]
        case .aiff: [["pcm_s16be"]]
        case .flac: [["flac"]]
        case .ogg: [["libvorbis"]]
        case .opus: [["libopus"]]
        case .wma: [["wmav2"]]
        case .mp4, .mov: fromGIF ? [h264] : [h264, ["aac_at"]]
        case .mkv: fromGIF ? [h264] : []
        case .webm: fromGIF ? [["libvpx-vp9"]] : [["libvpx-vp9"], ["libopus"]]
        case .avi: fromGIF ? [["mpeg4"]] : [["mpeg4"], ["libmp3lame"]]
        case .wmv: fromGIF ? [["wmv2"]] : [["wmv2"], ["wmav2"]]
        case .gif: [["gif"]]
        default: []
        }
    }
}

/// Encoders and filters named by a planned argv.
enum FFmpegRequirements {
    static let graphFlags: Set<String> = ["-vf", "-af", "-filter_complex"]

    /// Values of `-c`, `-c:v`, `-c:a:1`, … except `copy`, first occurrence order.
    static func encoders(in argv: [String]) -> [String] {
        values(in: argv) { $0 == "-c" || $0.hasPrefix("-c:") }.filter { $0 != "copy" }.uniqued()
    }

    static func filters(in argv: [String]) -> [String] {
        values(in: argv, flag: graphFlags.contains).flatMap(filterNames).uniqued()
    }

    /// Filter names in a graph: split at "," and ";" outside single quotes, drop "[label]" prefixes, cut at "=".
    static func filterNames(_ graph: String) -> [String] {
        segments(graph).compactMap { segment in
            var rest = Substring(segment)
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") { rest = rest[rest.index(after: close)...] }
            let name = rest.prefix { $0 != "=" && $0 != "[" }
            return name.isEmpty ? nil : String(name)
        }
    }

    private static func segments(_ graph: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quoted = false
        for character in graph {
            if character == "'" { quoted.toggle() }
            if !quoted, character == "," || character == ";" {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        return parts + [current]
    }

    private static func values(in argv: [String], flag: (String) -> Bool) -> [String] {
        zip(argv, argv.dropFirst()).compactMap { key, value in flag(key) ? value : nil }
    }
}

extension MediaCapabilities {
    /// VideoToolbox counts only when both the H.264 and HEVC encoders are present.
    init(_ capabilities: FFmpegCapabilities) {
        let encoders = capabilities.encoders
        self.init(videoToolbox: encoders.contains("h264_videotoolbox") && encoders.contains("hevc_videotoolbox"))
    }
}

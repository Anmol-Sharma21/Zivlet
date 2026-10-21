import Foundation
import Testing
import ZivletCore

/// The pairs the matrix runs (P1-61): every catalog pair whose source is a Phase 1 media or raster format (153), plus
/// the 8 SVG pairs pulled forward by D-M4-6.
enum MatrixPairs {
    static let categories: Set<FormatCategory> = [.raster, .svg, .audio, .video, .gif]

    static let all: [ConversionPair] = ConversionCatalog.standard.pairs.filter {
        categories.contains(FormatRegistry.standard.format($0.source).category)
    }

    static let phaseOne: [ConversionPair] = all.filter { $0.source != .svg }

    static func count(_ category: FormatCategory) -> Int {
        all.count { FormatRegistry.standard.format($0.source).category == category }
    }

    /// For PRs: one pair per source format, then one more for each target not yet covered, in catalog order. Each
    /// source takes its first target that the subset does not have yet.
    static let subset: [ConversionPair] = {
        var chosen: [ConversionPair] = []
        var targets: Set<FormatID> = []
        for source in all.map(\.source).uniqued() {
            let row = all.filter { $0.source == source }
            guard let pick = row.first(where: { !targets.contains($0.target) }) ?? row.first else { continue }
            chosen.append(pick)
            targets.insert(pick.target)
        }
        for pair in all where !targets.contains(pair.target) {
            chosen.append(pair)
            targets.insert(pair.target)
        }
        return chosen
    }()
}

/// `ZIVLET_MATRIX=subset|full` turns the conversions on; anything else leaves them off.
enum MatrixEnvironment {
    static let variable = "ZIVLET_MATRIX"
    static var mode: String? { ProcessInfo.processInfo.environment[variable] }
    static var isEnabled: Bool { !pairs.isEmpty }
    static var pairs: [ConversionPair] { pairs(for: mode) }

    static func pairs(for mode: String?) -> [ConversionPair] {
        switch mode {
        case "subset": MatrixPairs.subset
        case "full": MatrixPairs.all
        default: []
        }
    }
}

/// The E1 fixture each source format converts from: the richer files where they exist (cover art, subtitles and
/// chapters, 24-bit, 5.1, alpha, deep P3).
enum MatrixFixtures {
    static let primary: [FormatID: String] = [
        .jpg: "srgb.jpg", .png: "alpha.png", .webp: "srgb.webp", .heic: "srgb.heic", .tiff: "p3-16bit.tiff",
        .avif: "srgb.avif", .bmp: "srgb.bmp", .svg: "drawing.svg",
        .mp3: "cover.mp3", .m4a: "tone.m4a", .wav: "pcm24.wav", .flac: "surround.flac", .ogg: "vorbis.ogg",
        .opus: "mono.opus", .aiff: "tone.aiff", .wma: "tone.wma",
        .mp4: "sdr-h264.mp4", .mov: "rotated.mov", .mkv: "subs-chapters.mkv", .webm: "vp9-opus.webm",
        .avi: "pcm.avi", .wmv: "wmv2.wmv", .gif: "transparent.gif",
    ]
}

extension ConversionPair: CustomTestStringConvertible {
    public var testDescription: String { "\(source.rawValue) → \(target.rawValue)" }
}

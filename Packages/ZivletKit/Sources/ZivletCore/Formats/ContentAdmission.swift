import Foundation

/// Decides which format a dropped file is converted as (03a §3.2): the sniffed type wins over the extension. Files
/// whose content and name belong to one container family keep the named format (an MP4 named `.mov` is still read
/// by the same demuxer), so only a real mismatch changes the route or refuses the file.
public enum ContentAdmission {
    public struct Verdict: Sendable, Equatable {
        public let format: FormatID
        /// True when the content overrode the extension (the card says so).
        public let isSniffed: Bool

        public init(format: FormatID, isSniffed: Bool) {
            self.format = format
            self.isSniffed = isSniffed
        }
    }

    /// Formats that share a container or a decoder, so content of one under the name of another is no mismatch.
    /// `gz` covers SVGZ; `mp3` under `flac` covers an ID3 tag longer than the header in front of FLAC.
    static let families: [Set<FormatID>] = [
        [.mp4, .mov, .m4a], [.heic, .avif], [.mkv, .webm], [.ogg, .opus], [.wma, .wmv], [.svg, .gz], [.mp3, .flac],
    ]

    /// `named` is the extension's format and `target` a catalog target for it. Unknown, refusable or unconvertible
    /// content throws `unsupportedInput(.contentMismatch)` before any engine opens the file.
    public static func resolve(
        named: FormatID, header: Data, target: FormatID, catalog: ConversionCatalog = .standard
    ) throws(JobError) -> Verdict {
        guard ContentSniffer.covered.contains(named) else { return Verdict(format: named, isSniffed: false) }
        guard case .format(let content) = ContentSniffer.classify(header) else {
            throw .unsupportedInput(.contentMismatch)
        }
        if content == named || families.contains(where: { $0.isSuperset(of: [named, content]) }) {
            return Verdict(format: named, isSniffed: false)
        }
        guard catalog.canConvert(content, to: target) else { throw .unsupportedInput(.contentMismatch) }
        return Verdict(format: content, isSniffed: true)
    }
}

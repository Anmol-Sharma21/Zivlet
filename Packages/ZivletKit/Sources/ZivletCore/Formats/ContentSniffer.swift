import Foundation

/// Names a file's real type from its first bytes (G-8, 03a §3.2), so a playlist, an archive or a picture with the
/// wrong extension is caught before any engine opens it. Pure: reads only the bytes it is given.
public enum ContentSniffer {
    /// Bytes admission reads from the start of a file.
    public static let headerLength = 4096

    public enum Classification: Sendable, Equatable {
        /// A format Zivlet reads.
        case format(FormatID)
        /// Something Zivlet names in order to refuse it: playlists, concat lists, streaming manifests, ZIP, PDF.
        case refusable
        case unknown
    }

    /// Inputs whose signatures this table knows; admission confirms these and leaves other formats alone.
    public static let covered: Set<FormatID> = [
        .jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .svg,
        .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma,
        .mp4, .mov, .mkv, .webm, .avi, .wmv, .gif,
    ]

    public static func sniff(_ header: Data) -> FormatID? {
        if case .format(let format) = classify(header) { return format }
        return nil
    }

    public static func classify(_ header: Data) -> Classification {
        let bytes = [UInt8](header.prefix(headerLength))
        if let format = binary(bytes) { return .format(format) }
        if isRefusable(bytes) { return .refusable }
        if let format = text(bytes) { return .format(format) }
        if MPEGAudio.findsFrame(in: bytes) { return .format(.mp3) }
        return .unknown
    }

    /// Fixed signatures at the start of the file, most specific first.
    static func binary(_ b: [UInt8]) -> FormatID? {
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpg }
        if b.starts(with: Array("GIF87a".utf8)) || b.starts(with: Array("GIF89a".utf8)) { return .gif }
        if b.starts(with: Array("II*\0".utf8)) || b.starts(with: Array("MM\0*".utf8)) { return .tiff }
        if b.starts(with: Array("fLaC".utf8)) { return .flac }
        if b.starts(with: Array("OggS".utf8)) { return contains(b, "OpusHead") ? .opus : .ogg }
        if b.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return contains(b.prefix(64), "webm") ? .webm : .mkv }
        if b.starts(with: [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11]) { return .wmv }
        if b.starts(with: [0x1F, 0x8B]) { return .gz }
        if b.starts(with: Array("ID3".utf8)) { return id3(b) }
        return riff(b) ?? form(b) ?? ISOMedia.format(b) ?? (b.starts(with: Array("BM".utf8)) ? .bmp : nil)
    }

    private static func riff(_ b: [UInt8]) -> FormatID? {
        guard b.count >= 12, ["RIFF", "RF64", "BW64"].contains(ascii(b[0..<4])) else { return nil }
        switch ascii(b[8..<12]) {
        case "WAVE": return .wav
        case "WEBP": return .webp
        case "AVI ": return .avi
        default: return nil
        }
    }

    private static func form(_ b: [UInt8]) -> FormatID? {
        guard b.count >= 12, ascii(b[0..<4]) == "FORM", ["AIFF", "AIFC"].contains(ascii(b[8..<12])) else {
            return nil
        }
        return .aiff
    }

    /// An ID3v2 tag fronts MP3 and sometimes FLAC: look past it when the tag ends inside the header.
    private static func id3(_ b: [UInt8]) -> FormatID {
        guard b.count >= 10 else { return .mp3 }
        let size = b[6..<10].reduce(0) { ($0 << 7) | (Int($1) & 0x7F) }
        let end = 10 + size
        guard end + 4 <= b.count else { return .mp3 }
        return Array(b[end..<end + 4]) == Array("fLaC".utf8) ? .flac : .mp3
    }

    static func isRefusable(_ b: [UInt8]) -> Bool {
        let zip: [[UInt8]] = [[0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06], [0x50, 0x4B, 0x07, 0x08]]
        if zip.contains(where: { b.starts(with: $0) }) || b.starts(with: Array("Rar!\u{1A}\u{7}".utf8)) { return true }
        let lead = leadingText(b)
        let prefixes = ["#EXTM3U", "ffconcat version", "%PDF-", "[playlist]"]
        return prefixes.contains { lead.hasPrefix($0) } || (lead.hasPrefix("<") && lead.contains("<MPD"))
    }

    /// SVG is XML text with an `<svg` element in the first 4 KB.
    private static func text(_ b: [UInt8]) -> FormatID? {
        let lead = leadingText(b)
        return lead.hasPrefix("<") && lead.contains("<svg") ? .svg : nil
    }

    /// The header as text without a byte-order mark or leading white space. Decoding is lossy, so a character cut
    /// at the 4 KB boundary does not hide the rest.
    private static func leadingText(_ b: [UInt8]) -> String {
        let body = b.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(b.dropFirst(3)) : b
        return String(String(decoding: body, as: UTF8.self).drop { $0.isWhitespace })
    }

    static func contains(_ bytes: some Collection<UInt8>, _ marker: String) -> Bool {
        let needle = Array(marker.utf8)
        let haystack = Array(bytes)
        guard haystack.count >= needle.count else { return false }
        return (0...(haystack.count - needle.count)).contains { haystack[$0..<$0 + needle.count].elementsEqual(needle) }
    }

    static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}

/// ISO base media files (MP4, MOV, M4A, HEIF, AVIF): the `ftyp` brand, or a bare QuickTime atom.
enum ISOMedia {
    static let heifBrands: Set<String> = ["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1"]
    static let quickTimeAtoms: Set<String> = ["moov", "mdat", "wide", "free", "skip", "pnot"]

    static func format(_ b: [UInt8]) -> FormatID? {
        guard b.count >= 12 else { return nil }
        let box = ContentSniffer.ascii(b[4..<8])
        guard box == "ftyp" else { return quickTimeAtoms.contains(box) ? .mov : nil }
        let size = b[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        let end = min(max(size, 16), b.count)
        let compatible = stride(from: 16, to: end - 3, by: 4).map { ContentSniffer.ascii(b[$0..<$0 + 4]) }
        return brand(ContentSniffer.ascii(b[8..<12]), compatible: compatible)
    }

    static func brand(_ major: String, compatible: [String]) -> FormatID {
        if major == "avif" || major == "avis" || (heifBrands.contains(major) && compatible.contains("avif")) {
            return .avif
        }
        if heifBrands.contains(major) { return .heic }
        switch major {
        case "qt  ": return .mov
        case "M4A ", "M4B ", "M4P ": return .m4a
        default: return .mp4
        }
    }
}

/// MPEG audio frame headers, for MP3 files without an ID3 tag.
enum MPEGAudio {
    /// A frame sync with a valid version, layer, bitrate and sample rate anywhere in the header.
    static func findsFrame(in b: [UInt8]) -> Bool {
        guard b.count >= 4 else { return false }
        return (0..<(b.count - 3)).contains { isFrameHeader(b[$0], b[$0 + 1], b[$0 + 2]) }
    }

    static func isFrameHeader(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Bool {
        guard b0 == 0xFF, b1 & 0xE0 == 0xE0 else { return false }
        let version = (b1 >> 3) & 0x3
        let layer = (b1 >> 1) & 0x3
        let bitrate = b2 >> 4
        let rate = (b2 >> 2) & 0x3
        return version != 1 && layer != 0 && bitrate != 0xF && bitrate != 0 && rate != 3
    }
}

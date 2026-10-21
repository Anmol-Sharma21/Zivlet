import Foundation

/// A proposed output name before collision handling. `ext == nil` means a folder.
/// Invariant: the rendered name is one safe path component. The stem is sanitised (`FileNameRules.safeStem`) and NFC;
/// the extension matches `[a-z0-9]+(\.[a-z0-9]+)*` and is at most 16 bytes.
public struct OutputName: Sendable, Hashable, Codable {
    public static let maxBytes = 255

    public let stem: String
    public let ext: String?

    /// Sanitises `stem`; refuses an extension outside the rule above.
    public init(stem: String, ext: String?) throws(NamingError) {
        if let ext, !FileNameRules.isValidExtension(ext) { throw .invalidExtension(ext) }
        self.init(stem: stem, validExtension: ext)
    }

    /// For extensions already known to be valid (a `Format`'s, or a literal).
    init(stem: String, validExtension ext: String?) {
        self.stem = FileNameRules.safeStem(stem).precomposedStringWithCanonicalMapping
        self.ext = ext
    }

    public var isFolder: Bool { ext == nil }

    /// `counter` 2, 3, … appends " 2" before the extension (03a §4.4). Stem is truncated grapheme-safely
    /// so the UTF-8 name never exceeds 255 bytes.
    public func rendered(counter: Int? = nil) -> String {
        let tail = (counter.map { " \($0)" } ?? "") + (ext.map { ".\($0)" } ?? "")
        var stem = self.stem
        while !stem.isEmpty, (stem + tail).utf8.count > Self.maxBytes { stem.removeLast() }
        return stem + tail
    }
}

extension OutputName {
    private enum CodingKeys: String, CodingKey { case stem, ext }

    /// Decoding goes through `init(stem:ext:)`, so decoded names get the same sanitising and checks.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stem = try container.decode(String.self, forKey: .stem)
        let ext = try container.decodeIfPresent(String.self, forKey: .ext)
        do {
            try self.init(stem: stem, ext: ext)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .ext, in: container, debugDescription: "Invalid output extension")
        }
    }
}

import Foundation

/// Why the fixture manifest or a rendering was refused.
public enum OCRFixtureError: Error, Equatable, Sendable {
    case unreadableManifest(String)
    case unsupportedVersion(Int)
    case duplicateName(String)
    case emptyText(String)
    case unknownFont(String)
    case sizeOutOfRange(String, Int)
    /// The font is not installed under its PostScript name.
    case fontMissing(String)
    /// CoreText drew part of the fixture with another font: the test fails instead of measuring a fallback.
    case fontFallback(fixture: String, used: String)
    case renderFailed(String)
}

/// The 12 Hindi + English fixtures (plan 18d, D-M6-11): sentences written for Zivlet, drawn at test time with fonts
/// that ship with macOS. Nothing but the manifest is committed.
public enum OCRFixtures {
    /// The fonts a fixture may name, by PostScript name; all ship with macOS.
    public static let knownFonts: Set<String> = [
        "HelveticaNeue", "KohinoorDevanagari-Regular", "DevanagariSangamMN", "ITFDevanagari-Book",
        "TimesNewRomanPSMT",
    ]
    public static let sizes = 8...96

    public enum Style: String, Codable, Sendable {
        /// Black on white.
        case plain
        /// White on `#1F2129`.
        case dark
        /// Black on white, then the fixed degradation chain and a JPEG (`Degradation.fixture`).
        case degraded
    }

    public struct Entry: Codable, Sendable, Equatable, CustomStringConvertible {
        public let name: String
        public let font: String
        /// The one other font CoreText may use, for characters `font` lacks (ITF Devanagari has no Latin letters);
        /// any other font still fails the rendering.
        public let fallback: String?
        public let size: Int
        public let style: Style
        public let lines: [String]

        public init(name: String, font: String, fallback: String? = nil, size: Int, style: Style, lines: [String]) {
            self.name = name
            self.font = font
            self.fallback = fallback
            self.size = size
            self.style = style
            self.lines = lines
        }

        /// The ground truth: the lines joined by line breaks.
        public var text: String { lines.joined(separator: "\n") }

        public var fileName: String { name + (style == .degraded ? ".jpg" : ".png") }

        /// Swift Testing shows this for a parameterised fixture.
        public var description: String { name }
    }

    public struct Manifest: Codable, Sendable, Equatable {
        public let version: Int
        public let entries: [Entry]

        /// Decodes and validates: version 1, unique names, non-empty text, known fonts, sizes 8…96.
        public static func decode(_ data: Data) throws(OCRFixtureError) -> Manifest {
            let manifest: Manifest
            do {
                manifest = try JSONDecoder().decode(Manifest.self, from: data)
            } catch {
                throw .unreadableManifest(String(describing: error))
            }
            try manifest.validate()
            return manifest
        }

        func validate() throws(OCRFixtureError) {
            guard version == 1 else { throw .unsupportedVersion(version) }
            var seen: Set<String> = []
            for entry in entries {
                guard seen.insert(entry.name).inserted else { throw .duplicateName(entry.name) }
                let blank = entry.text.allSatisfy { $0.isWhitespace || $0.isNewline }
                guard !blank else { throw .emptyText(entry.name) }
                let fonts = [entry.font] + (entry.fallback.map { [$0] } ?? [])
                for font in fonts where !OCRFixtures.knownFonts.contains(font) { throw .unknownFont(font) }
                guard OCRFixtures.sizes.contains(entry.size) else { throw .sizeOutOfRange(entry.name, entry.size) }
            }
        }
    }

    /// The committed manifest, decoded and validated.
    public static func manifest() throws(OCRFixtureError) -> Manifest {
        guard let url = Bundle.module.url(forResource: "ocr-fixtures", withExtension: "json") else {
            throw .unreadableManifest("ocr-fixtures.json is not in the bundle")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadableManifest(String(describing: error))
        }
        return try Manifest.decode(data)
    }

    /// The entries for a parameterised test; empty when the manifest is broken (its own test then fails).
    public static var entries: [Entry] { (try? manifest().entries) ?? [] }

    /// Writes every fixture into `folder` and returns the files in manifest order.
    @discardableResult
    public static func render(into folder: URL) throws -> [URL] {
        try manifest().entries.map { entry in
            let file = folder.appending(path: entry.fileName, directoryHint: .notDirectory)
            try encoded(entry).write(to: file)
            return file
        }
    }
}

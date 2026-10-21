/// Immutable lookup over the format table: by id, by file name, by UTI (P0-10).
/// Invariant: every `FormatID` appears exactly once, so `format(_:)` is total.
public struct FormatRegistry: Sendable {
    /// The built-in table; `CatalogValidationTests` checks it against `init(formats:)`.
    public static let standard = FormatRegistry(validated: table)

    public let formats: [Format]
    private let byID: [FormatID: Format]
    private let byExtension: [String: FormatID]
    /// Extensions that contain a dot ("tar.gz"), longest first, matched before the single-extension lookup.
    private let compoundExtensions: [(ext: String, id: FormatID)]

    /// Refuses a table that misses a `FormatID` or lists one twice.
    public init(formats: [Format]) throws(CatalogError) {
        var seen: Set<FormatID> = []
        for format in formats where !seen.insert(format.id).inserted { throw .duplicateFormat(format.id) }
        if let missing = FormatID.allCases.first(where: { !seen.contains($0) }) { throw .missingFormat(missing) }
        self.init(validated: formats)
    }

    private init(validated formats: [Format]) {
        self.formats = formats
        self.byID = Dictionary(formats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pairs = formats.flatMap { format in format.extensions.map { ($0.lowercased(), format.id) } }
        self.byExtension = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        self.compoundExtensions =
            pairs
            .filter { $0.0.contains(".") }
            .sorted { $0.0.count > $1.0.count }
            .map { (ext: $0.0, id: $0.1) }
    }

    /// The format for `id`. Total: both initialisers guarantee every `FormatID` is present.
    public func format(_ id: FormatID) -> Format {
        guard let format = byID[id] else {
            preconditionFailure("Format table has no entry for \(id)")
        }
        return format
    }

    /// The format named by the file's extension, case-insensitive; nil when unknown or extensionless.
    public func formatID(fileName: String) -> FormatID? {
        let lowered = fileName.lowercased()
        if let compound = compoundExtensions.first(where: { Self.hasCompoundSuffix(lowered, $0.ext) }) {
            return compound.id
        }
        guard let ext = FileNameParts(lowered).extension else { return nil }
        return byExtension[ext]
    }

    /// The file-name extension wins; otherwise the UTI must belong to exactly one format.
    public func formatID(contentType: String, fileName: String) -> FormatID? {
        if let id = formatID(fileName: fileName) { return id }
        let matches = formats.filter { $0.contentTypes.contains(contentType) }
        return matches.count == 1 ? matches[0].id : nil
    }

    private static func hasCompoundSuffix(_ name: String, _ ext: String) -> Bool {
        let suffix = "." + ext
        return name.count > suffix.count && name.hasSuffix(suffix)
    }
}

/// A file name split at its last dot. A leading dot belongs to the stem (`.hidden`, `.png`); a trailing dot gives
/// no extension (`trailingdot.`).
struct FileNameParts: Equatable {
    let stem: String
    let `extension`: String?

    init(_ fileName: String) {
        guard let dot = fileName.lastIndex(of: "."),
            dot != fileName.startIndex,
            fileName.index(after: dot) != fileName.endIndex
        else {
            self.stem = fileName
            self.extension = nil
            return
        }
        self.stem = String(fileName[..<dot])
        self.extension = String(fileName[fileName.index(after: dot)...])
    }
}

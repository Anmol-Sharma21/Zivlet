/// One file format Zivlet reads or writes (03a §3.1). Immutable value; the data lives in `FormatTable.swift`.
/// Invariant: at least one valid extension and one content type, enforced by `init` (package data) and by decoding.
public struct Format: Sendable, Hashable, Codable {
    public let id: FormatID
    public let family: FormatFamily
    public let category: FormatCategory
    public let role: FormatRole
    /// Lower-case extensions without the dot. The first is the canonical output extension ("tar.gz" for gz).
    public let extensions: [String]
    /// Uniform type identifiers. The first is the preferred one.
    public let contentTypes: [String]
    /// A directory bundle accepted as one file (pages, rtfd; 03a §3.1).
    public let isPackage: Bool

    /// Package-only: the format table is static data checked by tests; other callers obtain formats by decoding.
    package init(
        _ id: FormatID, _ family: FormatFamily, _ category: FormatCategory, role: FormatRole = .inputAndOutput,
        extensions: [String], contentTypes: [String], isPackage: Bool = false
    ) {
        precondition(Self.isValid(extensions: extensions, contentTypes: contentTypes), "Format \(id) is invalid")
        self.id = id
        self.family = family
        self.category = category
        self.role = role
        self.extensions = extensions
        self.contentTypes = contentTypes
        self.isPackage = isPackage
    }

    public var canonicalExtension: String { extensions[0] }

    /// Upper-case extension shown on a wheel slice; gz reads "GZIP" (03a §3.1).
    public var wheelLabel: String { id == .gz ? "GZIP" : id.rawValue.uppercased() }

    public var isInput: Bool { role != .outputOnly }

    public var isOutput: Bool { role != .inputOnly }
}

extension Format {
    private enum CodingKeys: String, CodingKey { case id, family, category, role, extensions, contentTypes, isPackage }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let extensions = try c.decode([String].self, forKey: .extensions)
        let contentTypes = try c.decode([String].self, forKey: .contentTypes)
        guard Self.isValid(extensions: extensions, contentTypes: contentTypes) else {
            throw DecodingError.dataCorruptedError(
                forKey: .extensions, in: c, debugDescription: "A format needs valid extensions and content types")
        }
        self.init(
            try c.decode(FormatID.self, forKey: .id), try c.decode(FormatFamily.self, forKey: .family),
            try c.decode(FormatCategory.self, forKey: .category), role: try c.decode(FormatRole.self, forKey: .role),
            extensions: extensions, contentTypes: contentTypes, isPackage: try c.decode(Bool.self, forKey: .isPackage))
    }

    static func isValid(extensions: [String], contentTypes: [String]) -> Bool {
        !extensions.isEmpty && !contentTypes.isEmpty && extensions.allSatisfy(FileNameRules.isValidExtension)
            && !contentTypes.contains(where: \.isEmpty)
    }
}

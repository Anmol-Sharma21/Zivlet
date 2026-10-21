import Foundation

/// Character rules shared by format extensions and output names.
enum FileNameRules {
    /// Stem used when the source name leaves nothing usable ("", whitespace, ".", "..").
    static let fallbackStem = "Untitled"
    static let replacement: Unicode.Scalar = "-"

    /// One path component: "/", ":" and control characters (Unicode Cc, NUL included) become "-".
    static func safeStem(_ raw: String) -> String {
        let mapped = String(String.UnicodeScalarView(raw.unicodeScalars.map { isUnsafe($0) ? replacement : $0 }))
        let visible = mapped.trimmingCharacters(in: .whitespaces)
        return visible.isEmpty || visible == "." || visible == ".." ? fallbackStem : mapped
    }

    private static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "/" || scalar == ":" || scalar.properties.generalCategory == .control
    }
    /// The longest extension accepted, so a stem always keeps room inside the 255-byte name limit.
    static let maxExtensionBytes = 16

    /// Lower-case ASCII letters and digits, optionally dot-separated ("png", "tar.gz").
    static func isValidExtension(_ ext: String) -> Bool {
        guard !ext.isEmpty, ext.utf8.count <= maxExtensionBytes else { return false }
        let parts = ext.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        }
    }
}

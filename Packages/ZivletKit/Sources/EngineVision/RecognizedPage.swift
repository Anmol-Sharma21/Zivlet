/// The writing systems found in recognised text; Devanagari is called Hindi in the interface (plan 18d D6).
public enum Script: String, Codable, Sendable, Hashable, CaseIterable {
    case devanagari, latin, other
}

/// The text of one image or one PDF page.
public struct RecognizedPage: Codable, Sendable, Equatable {
    public let text: String
    public let scripts: Set<Script>

    public init(text: String) {
        self.text = text
        scripts = Self.scripts(in: text)
    }

    /// Nothing but whitespace.
    public var isEmpty: Bool { text.allSatisfy { $0.isWhitespace || $0.isNewline } }

    /// The script of every letter: digits, punctuation and symbols count for none.
    static func scripts(in text: String) -> Set<Script> {
        Set(text.unicodeScalars.compactMap(script(of:)))
    }

    static func script(of scalar: Unicode.Scalar) -> Script? {
        let value = scalar.value
        if (0x0900...0x097F).contains(value) || (0xA8E0...0xA8FF).contains(value) { return .devanagari }
        guard scalar.properties.isAlphabetic else { return nil }
        let latin = (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) || (0xC0...0x24F).contains(value)
        return latin ? .latin : .other
    }
}

import Foundation

/// A recognition language as a small Codable value that can cross to the worker; it becomes a `Locale.Language` only
/// inside the recognizer.
public struct LanguageTag: Codable, Sendable, Hashable, CustomStringConvertible {
    /// ISO 639 code, for example `hi`.
    public let code: String
    /// ISO 15924 script, for example `Deva`.
    public let script: String

    public init(code: String, script: String) {
        self.code = code
        self.script = script
    }

    public static let hindi = LanguageTag(code: "hi", script: "Deva")
    public static let english = LanguageTag(code: "en", script: "Latn")

    /// `hi-Deva`, the BCP 47 form Vision accepts.
    public var identifier: String { "\(code)-\(script)" }

    public var description: String { identifier }

    public var localeLanguage: Locale.Language { Locale.Language(identifier: identifier) }
}

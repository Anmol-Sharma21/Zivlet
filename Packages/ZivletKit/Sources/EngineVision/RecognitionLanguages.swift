import Foundation
import ZivletCore

/// The ordered languages a recognition uses (P2-103, OWN-OCR-1). Order matters: with English first, Vision drops
/// Devanagari silently (17c §1.4), so Hindi always comes first and English last. Automatic language detection is
/// never turned on.
public enum RecognitionLanguages {
    /// Language codes that make "Match my languages" read Hindi: Hindi and Marathi share Devanagari.
    static let devanagariCodes: Set<String> = ["hi", "mr"]
    /// Words in an input source id that mean a Devanagari keyboard.
    static let devanagariSourceWords = ["devanagari", "hindi", "marathi"]

    public static func defaults(
        preferred: [String], inputSources: [String], choice: TextLanguageChoice, hindiAvailable: Bool
    ) -> [LanguageTag] {
        guard hindiAvailable else { return [.english] }
        switch choice {
        case .english: return [.english]
        case .hindiAndEnglish: return [.hindi, .english]
        case .matchMine:
            let wantsHindi =
                preferred.contains(where: isDevanagariLanguage) || inputSources.contains(where: isDevanagariSource)
            return wantsHindi ? [.hindi, .english] : [.english]
        }
    }

    /// `hi-IN`, `hi_IN`, `mr` and the like.
    static func isDevanagariLanguage(_ identifier: String) -> Bool {
        let code = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return devanagariCodes.contains(code.lowercased())
    }

    /// `com.apple.keylayout.Devanagari-QWERTY`, a Hindi input method and the like.
    static func isDevanagariSource(_ id: String) -> Bool {
        let lowered = id.lowercased()
        return devanagariSourceWords.contains { lowered.contains($0) }
    }
}

import EngineVision
import Testing
import ZivletCore

@Suite("Recognition languages (P2-103): Hindi first for Hindi and Marathi users, never auto-detect")
struct RecognitionLanguagesTests {
    struct Row: Sendable, CustomStringConvertible {
        let preferred: [String]
        let sources: [String]
        let choice: TextLanguageChoice
        let hindi: Bool
        let expected: [LanguageTag]

        var description: String { "\(preferred) \(sources) \(choice) hindi=\(hindi)" }
    }

    static let rows: [Row] = [
        Row(
            preferred: ["en-IN", "hi-IN"], sources: [], choice: .matchMine, hindi: true, expected: [.hindi, .english]),
        Row(preferred: ["en-US"], sources: [], choice: .matchMine, hindi: true, expected: [.english]),
        Row(preferred: ["mr-IN"], sources: [], choice: .matchMine, hindi: true, expected: [.hindi, .english]),
        Row(
            preferred: ["en-GB"], sources: ["com.apple.keylayout.Devanagari-QWERTY"], choice: .matchMine, hindi: true,
            expected: [.hindi, .english]),
        Row(
            preferred: ["en-GB"], sources: ["com.apple.keylayout.British"], choice: .matchMine, hindi: true,
            expected: [.english]),
        Row(preferred: ["hi"], sources: [], choice: .matchMine, hindi: false, expected: [.english]),
        Row(preferred: ["en-US"], sources: [], choice: .hindiAndEnglish, hindi: true, expected: [.hindi, .english]),
        Row(preferred: ["en-US"], sources: [], choice: .hindiAndEnglish, hindi: false, expected: [.english]),
        Row(preferred: ["hi-IN"], sources: [], choice: .english, hindi: true, expected: [.english]),
        Row(preferred: ["hi_IN"], sources: [], choice: .matchMine, hindi: true, expected: [.hindi, .english]),
        Row(preferred: [], sources: [], choice: .matchMine, hindi: true, expected: [.english]),
    ]

    @Test(arguments: rows)
    func defaultsFollowTheRule(_ row: Row) {
        let languages = RecognitionLanguages.defaults(
            preferred: row.preferred, inputSources: row.sources, choice: row.choice, hindiAvailable: row.hindi)
        #expect(languages == row.expected)
    }

    @Test func englishIsAlwaysLastWhenHindiIsFirst() {
        for row in Self.rows {
            let languages = RecognitionLanguages.defaults(
                preferred: row.preferred, inputSources: row.sources, choice: row.choice, hindiAvailable: row.hindi)
            if languages.first == .hindi { #expect(languages.last == .english) }
            #expect(languages.contains(.english))
        }
    }

    @Test func tagsKnowTheirCodeAndScript() {
        #expect(LanguageTag.hindi.code == "hi" && LanguageTag.hindi.script == "Deva")
        #expect(LanguageTag.english.code == "en" && LanguageTag.english.script == "Latn")
        #expect(LanguageTag.hindi.identifier == "hi-Deva")
    }
}

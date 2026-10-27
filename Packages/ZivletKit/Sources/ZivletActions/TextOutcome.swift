import Foundation

/// The recognised text of one Copy Text drop, held by reference so the card is its only owner: when the card goes,
/// the text goes (P2-104, plan 18d D14). Immutable.
public final class TextHolder: Sendable {
    public let text: String

    public init(_ text: String) { self.text = text }
}

/// What the text card shows (P2-104): the first lines, the character count and scripts, any `.txt` files written
/// with ⌥, the Show All window's title, and the full text in memory only.
public struct TextOutcome: Sendable, Equatable {
    /// How long the card stays, held while hovered (plan 18d D11).
    public static let linger = Duration.seconds(8)

    public let preview: [String]
    public let characterCount: Int
    /// "Hindi and English"; empty when the text has no letters.
    public let scriptLine: String
    public let savedFiles: [URL]
    public let windowTitle: String
    public let text: TextHolder

    public init(
        preview: [String], characterCount: Int, scriptLine: String, savedFiles: [URL], windowTitle: String,
        text: TextHolder
    ) {
        self.preview = preview
        self.characterCount = characterCount
        self.scriptLine = scriptLine
        self.savedFiles = savedFiles
        self.windowTitle = windowTitle
        self.text = text
    }

    public var fullText: String { text.text }

    /// "342 characters · Hindi and English".
    public var countLine: String {
        let count = "\(characterCount) " + (characterCount == 1 ? "character" : "characters")
        return scriptLine.isEmpty ? count : "\(count) · \(scriptLine)"
    }

    public static func == (a: TextOutcome, b: TextOutcome) -> Bool {
        a.preview == b.preview && a.characterCount == b.characterCount && a.scriptLine == b.scriptLine
            && a.savedFiles == b.savedFiles && a.windowTitle == b.windowTitle && a.fullText == b.fullText
    }
}

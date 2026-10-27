import Foundation

/// One input's own text, for Save as Text (one `.txt` per input).
nonisolated public struct TextFile: Sendable, Equatable {
    public let source: URL
    public let text: String

    public init(source: URL, text: String) {
        self.source = source
        self.text = text
    }
}

/// The recognised text of one Copy Text drop, held by reference so the card is its only owner: when the card goes,
/// the text goes (P2-104, plan 18d D14). Immutable.
public final class TextHolder: Sendable {
    public let text: String
    /// Every input with text, in drop order.
    public let files: [TextFile]

    public init(_ text: String, files: [TextFile] = []) {
        self.text = text
        self.files = files
    }
}

/// What the text card shows (P2-104): the first lines, the character count and scripts, any `.txt` files written
/// with ⌥, the Show All window's title, and the full text in memory only. `notes` are caption lines about what went
/// wrong beside the text (files not read, the clipboard refused, `.txt` files not saved), so the text is kept and
/// Copy Again and Show All stay reachable. `copied` is false when the clipboard refused the text.
public struct TextOutcome: Sendable, Equatable {
    /// How long the card stays, held while hovered (plan 18d D11).
    public static let linger = Duration.seconds(8)
    public static let copiedHeadline = "Text copied"
    public static let notCopiedHeadline = "Text found"

    public let preview: [String]
    public let characterCount: Int
    /// "Hindi and English"; empty when the text has no letters.
    public let scriptLine: String
    public let savedFiles: [URL]
    public let windowTitle: String
    public let text: TextHolder
    public let notes: [String]
    public let copied: Bool

    public init(
        preview: [String], characterCount: Int, scriptLine: String, savedFiles: [URL], windowTitle: String,
        text: TextHolder, notes: [String] = [], copied: Bool = true
    ) {
        self.preview = preview
        self.characterCount = characterCount
        self.scriptLine = scriptLine
        self.savedFiles = savedFiles
        self.windowTitle = windowTitle
        self.text = text
        self.notes = notes
        self.copied = copied
    }

    public var fullText: String { text.text }

    /// "Text copied", or "Text found" when the clipboard refused it.
    public var headline: String { copied ? Self.copiedHeadline : Self.notCopiedHeadline }

    /// "342 characters · Hindi and English".
    public var countLine: String {
        let count = "\(characterCount) " + (characterCount == 1 ? "character" : "characters")
        return scriptLine.isEmpty ? count : "\(count) · \(scriptLine)"
    }

    public static func == (a: TextOutcome, b: TextOutcome) -> Bool {
        a.preview == b.preview && a.characterCount == b.characterCount && a.scriptLine == b.scriptLine
            && a.savedFiles == b.savedFiles && a.windowTitle == b.windowTitle && a.fullText == b.fullText
            && a.notes == b.notes && a.copied == b.copied
    }
}

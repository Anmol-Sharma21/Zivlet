import EngineVision
import Foundation
import ZivletActions

/// The pure part of Copy Text's wiring (P2-104, plan 18d D12): the working line, the result for the presenters and
/// Zivlet's own sentence for every error. The app's `ToolWiring` does the side effects.
public enum ToolWiringModel {
    public static let preparing = "Preparing text recognition (one time)…"
    public static let recognising = "Recognising text…"
    public static let noText = "No text found"
    /// "No text found" when the choice would read Hindi but this Mac's Vision has none (only English was read).
    public static let noTextWithoutHindi = "No text found. Hindi isn't available on this Mac."
    /// What the island's tab shows while Copy Text works.
    public static let workingSymbol = "text.viewfinder"

    /// Until the first page or file is read, a job that waits for the one-time preparation says so; the preparation
    /// happens inside Vision's first request and reports no progress, so the line has no percent until then (D-M6-20).
    /// From the first progress on, the percent. A job never times out.
    public static func workingLine(warmupDone: Bool, fraction: Double?) -> String {
        guard let fraction else { return warmupDone ? recognising : preparing }
        return "\(recognising) \(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
    }

    /// The working line with its fraction and symbol, for the presenters.
    public static func working(warmupDone: Bool, fraction: Double?) -> WorkingStatus {
        WorkingStatus(
            line: workingLine(warmupDone: warmupDone, fraction: fraction), fraction: fraction, symbol: workingSymbol)
    }

    /// ⌥ writes one `.txt` per input beside it.
    public static func writesFiles(optionHeld: Bool) -> Bool { optionHeld }

    /// The text card with notes for what went wrong beside it; "No text found" (not an error, P2-104); or, when no
    /// file could be read, a card naming each. `sources` are the inputs in drop order.
    public static func result(
        _ text: RecognizedText, sources: [URL], delivery: TextDelivery = .copied, skipsHindi: Bool = false
    ) -> ActionResult {
        guard !text.isEmpty else { return empty(text, skipsHindi: skipsHindi) }
        let files = zip(sources, text.perFile).filter { !$0.1.isEmpty }.map { TextFile(source: $0.0, text: $0.1.text) }
        let notes =
            TextCopy.listed(TextCopy.notRead(text.skipped.count), text.skipped.map(TextCopy.line))
            + (delivery.copied ? [] : [TextCopy.clipboardRefused])
            + TextCopy.listed(TextCopy.notSaved(delivery.notSaved.count), delivery.notSaved.map(TextCopy.line))
        return .text(
            TextOutcome(
                preview: text.preview, characterCount: text.characterCount,
                scriptLine: ScriptSummary.line(text.scripts), savedFiles: delivery.saved,
                windowTitle: TextPreviewModel.title(names: text.perFile.map(\.name)),
                text: TextHolder(text.text, files: files), notes: notes, copied: delivery.copied))
    }

    /// No text: "No text found", or a card naming the files that could not be read (a toast too when others had none).
    static func empty(_ text: RecognizedText, skipsHindi: Bool) -> ActionResult {
        let toast = skipsHindi ? noTextWithoutHindi : noText
        guard let first = text.skipped.first else { return .done(toast: toast, undo: nil) }
        if text.perFile.count == 1 {
            return .failed(ActionCard(title: sentence(first.error) ?? noText, lines: [first.name]))
        }
        let card = ActionCard(title: TextCopy.notRead(text.skipped.count), lines: text.skipped.map(TextCopy.line))
        return text.skipped.count == text.perFile.count ? .failed(card) : .partial(toast: toast, card: card, undo: nil)
    }

    /// Save as Text: "Saved 3 text files", with a card for the files that were not saved.
    public static func saved(_ delivery: TextDelivery) -> ActionResult {
        guard !delivery.notSaved.isEmpty else { return .done(toast: savedToast(delivery.saved), undo: nil) }
        let card = ActionCard(
            title: TextCopy.notSaved(delivery.notSaved.count), lines: delivery.notSaved.map(TextCopy.line))
        guard !delivery.saved.isEmpty else { return .failed(card) }
        return .partial(toast: savedToast(delivery.saved), card: card, undo: nil)
    }

    /// Zivlet's own words for a failed job; a cancel shows nothing.
    public static func failure(_ error: TextError) -> ActionResult {
        guard let sentence = sentence(error) else { return .cancelled }
        return .failed(ActionCard(title: sentence))
    }

    static func sentence(_ error: TextError) -> String? {
        switch error {
        case .cancelled: nil
        case .unavailable: "Text recognition isn't available right now."
        case .copyingNotAllowed: "This PDF doesn't allow copying its text."
        case .pdfLocked: "This PDF is locked."
        case .engineCrashedOnInput: "This file made the engine crash."
        case .tooLarge: "This file is larger than Zivlet's safety limit."
        case .unreadable: "This file couldn't be read. It may be damaged."
        case .tooManyPages: "This PDF has more than \(PDFTextSource.pageLimit) pages."
        case .recognitionFailed: "Zivlet couldn't read the text in this file."
        case .tooManyFiles(let limit): "Copy Text reads up to \(limit) files at a time."
        }
    }

    /// "Saved photo Text.txt", or "Saved 3 text files".
    public static func savedToast(_ files: [URL]) -> String {
        files.count == 1 ? "Saved \(files[0].lastPathComponent)" : "Saved \(files.count) text files"
    }
}

/// What happened beside the recognised text: whether the clipboard took it, and the `.txt` files saved or not.
nonisolated public struct TextDelivery: Sendable, Equatable {
    public static let copied = TextDelivery(copied: true)

    public let copied: Bool
    public let saved: [URL]
    public let notSaved: [NotSavedFile]

    public init(copied: Bool, saved: [URL] = [], notSaved: [NotSavedFile] = []) {
        self.copied = copied
        self.saved = saved
        self.notSaved = notSaved
    }
}

/// A `.txt` file that was not written: its input's name and Zivlet's short reason.
nonisolated public struct NotSavedFile: Sendable, Equatable {
    public let name: String
    public let reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

/// The few words of Copy Text's notes and cards: a count line, then one short line per file.
enum TextCopy {
    static let shownLines = 3
    static let clipboardRefused = "Not copied: the clipboard refused it. Try Copy Again."

    static func notRead(_ count: Int) -> String {
        count == 1 ? "1 file couldn't be read." : "\(count) files couldn't be read."
    }

    static func notSaved(_ count: Int) -> String {
        count == 1 ? "1 text file wasn't saved." : "\(count) text files weren't saved."
    }

    /// The title and up to three lines, then "and 2 more"; nothing when there are no lines.
    static func listed(_ title: String, _ lines: [String]) -> [String] {
        guard !lines.isEmpty else { return [] }
        let hidden = lines.count - shownLines
        return [title] + lines.prefix(shownLines) + (hidden > 0 ? ["and \(hidden) more"] : [])
    }

    static func line(_ file: SkippedFile) -> String { "\(file.name) — \(reason(file.error))" }
    static func line(_ file: NotSavedFile) -> String { "\(file.name) — \(file.reason)" }

    static func reason(_ error: TextError) -> String {
        switch error {
        case .unreadable: "damaged, or not an image or PDF"
        case .copyingNotAllowed: "copying not allowed"
        case .pdfLocked: "locked"
        case .tooManyPages: "more than \(PDFTextSource.pageLimit) pages"
        case .tooLarge: "over the safety limit"
        case .recognitionFailed: "text couldn't be read"
        case .cancelled, .unavailable, .engineCrashedOnInput, .tooManyFiles: "not read"
        }
    }
}

import EngineVision
import Foundation
import ZivletActions

/// The pure part of Copy Text's wiring (P2-104, plan 18d D12): the working line, the result for the presenters and
/// Zivlet's own sentence for every error. The app's `ToolWiring` does the side effects.
public enum ToolWiringModel {
    public static let preparing = "Preparing text recognition (one time)…"
    public static let recognising = "Recognising text…"
    public static let noText = "No text found"
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

    /// The text card, or "No text found" (not an error, P2-104). `sources` are the inputs in drop order.
    public static func result(_ text: RecognizedText, sources: [URL], saved: [URL]) -> ActionResult {
        guard !text.isEmpty else { return .done(toast: noText, undo: nil) }
        let files = zip(sources, text.perFile).filter { !$0.1.isEmpty }.map { TextFile(source: $0.0, text: $0.1.text) }
        return .text(
            TextOutcome(
                preview: text.preview, characterCount: text.characterCount,
                scriptLine: ScriptSummary.line(text.scripts),
                savedFiles: saved, windowTitle: TextPreviewModel.title(names: text.perFile.map(\.name)),
                text: TextHolder(text.text, files: files)))
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
        }
    }

    /// "Saved photo Text.txt", or "Saved 3 text files".
    public static func savedToast(_ files: [URL]) -> String {
        files.count == 1 ? "Saved \(files[0].lastPathComponent)" : "Saved \(files.count) text files"
    }
}

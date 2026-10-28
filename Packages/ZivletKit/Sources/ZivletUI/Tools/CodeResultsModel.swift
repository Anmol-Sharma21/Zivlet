import EngineVision
import Foundation
import ZivletActions

/// One code in the results window: its payload in full, the file it came from, a caption (the symbology for a code
/// that is not QR, the page for a PDF, or "Not a web link"), and the web link Open may open.
public struct CodeRow: Sendable, Equatable, Identifiable {
    public let id: Int
    public let payload: String
    public let fileName: String
    public let caption: String?
    public let link: URL?

    public init(index: Int, code: FoundCode, fileName: String) {
        id = index
        payload = code.payload
        self.fileName = fileName
        link = CodeLink.webURL(code.payload)
        let kind = code.symbology == "qr" ? nil : CodeCopy.symbologyName(code.symbology)
        let page = code.page.map { "Page \($0)" }
        let other = CodeLink.isOtherLink(code.payload) ? CodeCopy.notWebLink : nil
        let parts = [kind, page, other].compactMap { $0 }
        caption = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The results window's content (D-M7-13): the shell's model, every row in order, the notes for files not read, and
/// the text Copy All writes (the payloads joined by line breaks).
public struct CodeResultsModel: Sendable, Equatable {
    public let window: ToolWindowModel
    public let rows: [CodeRow]
    public let notes: [String]

    public var copyAllText: String { rows.map(\.payload).joined(separator: "\n") }

    /// Rows carry their file's name as a heading when the codes came from more than one file.
    public var groupsByFile: Bool { Set(rows.map(\.fileName)).count > 1 }
}

/// What Read QR shows after its job: a toast or card in the HUD, or the results window.
public enum CodeResults: Sendable, Equatable {
    case toast(ActionResult)
    case window(CodeResultsModel)

    public static let symbol = "qrcode.viewfinder"

    /// No codes → "No codes found" (with a card for files not read); codes → the window, with a note per file not
    /// read. Rows keep the files' order, then each file's own order (page, then top to bottom).
    public static func present(_ files: [FileCodes]) -> CodeResults {
        let failed = files.filter { $0.error != nil }
        let lines = failed.compactMap { file in file.error.flatMap(CodeCopy.reason).map { "\(file.name): \($0)" } }
        let rows = files.flatMap { file in file.codes.map { (file.name, $0) } }.enumerated().map { index, pair in
            CodeRow(index: index, code: pair.1, fileName: pair.0)
        }
        guard rows.isEmpty else {
            let window = ToolWindowModel(
                symbol: symbol, title: CodeCopy.count(rows.count),
                fileLine: ToolWindowModel.fileLine(names: files.map(\.name)), apply: .enabled(label: CodeCopy.copyAll),
                cancelLabel: CodeCopy.close)
            let notes = failed.isEmpty ? [] : [CodeCopy.notRead(failed.count)] + lines
            return .window(CodeResultsModel(window: window, rows: rows, notes: notes))
        }
        guard let first = failed.first, let error = first.error else {
            return .toast(.done(toast: CodeCopy.noCodes, undo: nil))
        }
        if failed.count == files.count, files.count == 1 {
            return .toast(.failed(ActionCard(title: CodeCopy.reason(error) ?? CodeCopy.noCodes, lines: [first.name])))
        }
        let card = ActionCard(title: CodeCopy.notRead(failed.count), lines: lines)
        return .toast(
            failed.count == files.count ? .failed(card) : .partial(toast: CodeCopy.noCodes, card: card, undo: nil))
    }

    /// Zivlet's words for a job that failed as a whole; a cancel shows nothing.
    public static func failure(_ error: CodeError) -> ActionResult {
        guard let sentence = CodeCopy.jobSentence(error) else { return .cancelled }
        return .failed(ActionCard(title: sentence))
    }
}

/// Read QR's own words (plan 20b, new strings).
enum CodeCopy {
    static let noCodes = "No codes found"
    static let copyAll = "Copy All"
    static let close = "Close"
    static let notWebLink = "Not a web link"
    static let openHint = "Opens in your browser"

    static func count(_ count: Int) -> String { count == 1 ? "1 code" : "\(count) codes" }

    static func notRead(_ count: Int) -> String { count == 1 ? "1 file not read" : "\(count) files not read" }

    /// One file's reason, short, for its line on a card or a note.
    static func reason(_ error: CodeError) -> String? {
        switch error {
        case .unreadable: "This file couldn't be read"
        case .pdfLocked: "Needs a password"
        case .tooManyPages: "More than \(PDFTextSource.pageLimit) pages"
        case .tooLarge: "Larger than Zivlet's safety limit"
        case .detectionFailed: "Codes couldn't be read here"
        case .cancelled, .unavailable, .engineCrashedOnInput, .tooManyFiles: jobSentence(error)
        }
    }

    static func jobSentence(_ error: CodeError) -> String? {
        switch error {
        case .cancelled: nil
        case .unavailable: "Reading codes isn't available right now."
        case .engineCrashedOnInput: "This drop made the engine crash."
        case .tooManyFiles(let limit): "Read QR reads up to \(limit) files at a time."
        case .unreadable, .pdfLocked, .tooManyPages, .tooLarge, .detectionFailed: reason(error).map { $0 + "." }
        }
    }

    /// Vision's symbology names in the words printed under barcodes; an unknown one as Vision names it.
    static func symbologyName(_ symbology: String) -> String {
        let names = [
            "aztec": "Aztec", "code39": "Code 39", "code93": "Code 93", "code128": "Code 128",
            "dataMatrix": "Data Matrix", "ean8": "EAN-8", "ean13": "EAN-13", "upce": "UPC-E", "pdf417": "PDF417",
            "itf14": "ITF-14", "i2of5": "Interleaved 2 of 5", "codabar": "Codabar", "microQR": "Micro QR",
            "microPDF417": "MicroPDF417", "gs1DataBar": "GS1 DataBar",
        ]
        return names[symbology] ?? symbology
    }
}

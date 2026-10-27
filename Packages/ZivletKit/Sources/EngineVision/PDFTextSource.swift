import Foundation
import PDFKit

/// The text of a PDF, page by page (P2-104, D-M6-15). A locked file and one that disallows copying are refused
/// (OWN-PDF-5). A page's text layer is used when it is usable and has no Devanagari: PDFKit returns Devanagari in
/// visual order (17a L1), so those pages, scans and damaged layers are rendered at 300 DPI and recognised.
/// Cancellation is checked between pages; progress is pages done over pages.
public enum PDFTextSource {
    public static let pageLimit = 500

    public static func read(
        _ url: URL, recognizer: any TextRecognizing, languages: [LanguageTag], pageLimit: Int = pageLimit,
        progress: @Sendable (Double) -> Void
    ) async throws(TextError) -> [RecognizedPage] {
        let document = try open(url, pageLimit: pageLimit)
        var pages: [RecognizedPage] = []
        for index in 0..<document.pageCount {
            if Task.isCancelled { throw .cancelled }
            guard let page = document.page(at: index) else { throw .unreadable }
            pages.append(try await read(page, recognizer: recognizer, languages: languages))
            progress(Double(index + 1) / Double(document.pageCount))
        }
        return pages
    }

    static func open(_ url: URL, pageLimit: Int) throws(TextError) -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw .unreadable }
        guard !document.isLocked else { throw .pdfLocked }
        guard document.allowsCopying else { throw .copyingNotAllowed }
        guard document.pageCount <= pageLimit else { throw .tooManyPages(document.pageCount) }
        return document
    }

    static func read(_ page: PDFPage, recognizer: any TextRecognizing, languages: [LanguageTag]) async throws(TextError)
        -> RecognizedPage
    {
        let layer = normalizedLayer(page.string ?? "")
        let devanagari = layer.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
        if UsableText.isUsable(layer) && !devanagari { return RecognizedPage(text: layer) }
        return try await recognizer.recognize(try PageRenderer.render(page), languages: languages)
    }

    /// CRLF and CR become LF.
    public static func normalizedLayer(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

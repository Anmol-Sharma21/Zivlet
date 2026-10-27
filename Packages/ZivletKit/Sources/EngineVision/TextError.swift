/// Why text could not be read (P2-103, P2-104). Codable so it crosses from the worker; carries no user copy.
public enum TextError: Error, Sendable, Equatable, Codable {
    case cancelled
    /// Both Vision requests failed; the detail is Vision's own description, for the log only.
    case recognitionFailed(String)
    /// The file could not be opened as an image or a PDF.
    case unreadable
    /// OWN-PDF-5: the PDF's permissions refuse text extraction.
    case copyingNotAllowed
    /// The PDF needs a password.
    case pdfLocked
    /// More pages than the limit (`PDFTextSource.pageLimit`).
    case tooManyPages(Int)
}

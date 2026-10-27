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
    /// An image header above the decode limit (`ImageTextSource.maximumHeaderPixels`).
    case tooLarge
    /// No worker, or one without text recognition: Vision never runs in the app (D-M6-8).
    case unavailable
    /// The worker ended twice while reading this drop (P2-01's rule).
    case engineCrashedOnInput
}

extension TextError {
    /// The case for the log: never Vision's own description, which may name a file (NFR-6).
    public var logDescription: String {
        switch self {
        case .cancelled: "cancelled"
        case .recognitionFailed: "recognitionFailed"
        case .unreadable: "unreadable"
        case .copyingNotAllowed: "copyingNotAllowed"
        case .pdfLocked: "pdfLocked"
        case .tooManyPages(let count): "tooManyPages(\(count))"
        case .tooLarge: "tooLarge"
        case .unavailable: "unavailable"
        case .engineCrashedOnInput: "engineCrashedOnInput"
        }
    }
}

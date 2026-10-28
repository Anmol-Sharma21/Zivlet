/// Why codes could not be read (P2-51, plan 20b A7). Codable so it crosses from the worker; carries no user copy and
/// no text from Vision or the file.
public enum CodeError: Error, Sendable, Equatable, Codable {
    case cancelled
    /// Vision's barcode request failed on a page or image.
    case detectionFailed
    /// The file could not be opened as an image or a PDF.
    case unreadable
    /// The PDF needs a password (P2-107 adds the prompt).
    case pdfLocked
    /// More pages than the limit, which it carries.
    case tooManyPages(Int)
    /// An image header above the decode limit (`ImageTextSource.maximumHeaderPixels`).
    case tooLarge
    /// No worker, or one without Vision: Vision never runs in the app (D-M6-8).
    case unavailable
    /// The worker ended twice while reading this drop (P2-01's rule).
    case engineCrashedOnInput
    /// More files in one drop than the limit, which it carries.
    case tooManyFiles(limit: Int)
}

extension CodeError {
    /// The case for the log.
    public var logDescription: String {
        switch self {
        case .cancelled: "cancelled"
        case .detectionFailed: "detectionFailed"
        case .unreadable: "unreadable"
        case .pdfLocked: "pdfLocked"
        case .tooManyPages(let count): "tooManyPages(\(count))"
        case .tooLarge: "tooLarge"
        case .unavailable: "unavailable"
        case .engineCrashedOnInput: "engineCrashedOnInput"
        case .tooManyFiles(let limit): "tooManyFiles(\(limit))"
        }
    }

    /// Whether the error belongs to one file, so the rest of a drop goes on without it.
    public var isPerFile: Bool {
        switch self {
        case .cancelled, .unavailable, .engineCrashedOnInput, .tooManyFiles: false
        case .detectionFailed, .unreadable, .pdfLocked, .tooManyPages, .tooLarge: true
        }
    }

    /// The same failure as a text source reports it, for the decode and page code Copy Text shares.
    init(_ error: TextError) {
        switch error {
        case .cancelled: self = .cancelled
        case .pdfLocked: self = .pdfLocked
        case .tooManyPages(let count): self = .tooManyPages(count)
        case .tooLarge: self = .tooLarge
        case .unavailable: self = .unavailable
        case .engineCrashedOnInput: self = .engineCrashedOnInput
        case .tooManyFiles(let limit): self = .tooManyFiles(limit: limit)
        case .recognitionFailed: self = .detectionFailed
        case .unreadable, .copyingNotAllowed: self = .unreadable
        }
    }
}

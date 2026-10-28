import Foundation

/// One qpdf rewrite in the worker (P2-13, D-M7-16): the source PDF, what happens to its encryption and the page count
/// pre-flight found, which verify expects again. No password ever travels in a plan: a job's passwords come with its
/// own requests (plan 20f E3).
public struct PDFStage: Sendable, Codable, Equatable {
    public enum Encryption: String, Sendable, Codable {
        /// The output keeps the input's encryption (none stays none).
        case keep
        /// The output has no encryption.
        case remove
    }

    public let source: URL
    public let encryption: Encryption
    public let pageCount: Int

    public init(source: URL, encryption: Encryption, pageCount: Int) {
        self.source = source
        self.encryption = encryption
        self.pageCount = pageCount
    }
}

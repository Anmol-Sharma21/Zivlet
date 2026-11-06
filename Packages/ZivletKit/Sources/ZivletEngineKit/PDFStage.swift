import Foundation
import ZivletCore

/// One qpdf rewrite in the worker (P2-13, D-M7-16): the source PDF, what happens to its encryption and what
/// pre-flight found, which verify expects again. No password ever travels in a plan: a job's passwords come with its
/// own requests (plan 20f E3).
public struct PDFStage: Sendable, Codable, Equatable {
    public enum Encryption: Sendable, Codable, Equatable {
        /// The output keeps the input's encryption (none stays none).
        case keep
        /// The output has no encryption.
        case remove
        /// AES-256 R6 with the job's new user password; restrictions add its separate owner password (D-M7-20).
        case lock(PDFRestrictions?)
        /// AES-256 R6 with a new user password. `keepOwner`: the owner password typed as the current one and the
        /// input's permissions stay; otherwise the new password is both, with every permission (D-M7-22).
        case change(keepOwner: Bool)
    }

    public let source: URL
    public let encryption: Encryption
    public let pageCount: Int
    /// What the input allows, which Change keeps.
    public let permissions: PDFPermissions
    /// The input's form and signature fields, which every output keeps (FR-107).
    public let fieldCount: Int
    public let signatureFieldCount: Int

    public init(
        source: URL, encryption: Encryption, pageCount: Int, permissions: PDFPermissions = .all, fieldCount: Int = 0,
        signatureFieldCount: Int = 0
    ) {
        self.source = source
        self.encryption = encryption
        self.pageCount = pageCount
        self.permissions = permissions
        self.fieldCount = fieldCount
        self.signatureFieldCount = signatureFieldCount
    }
}

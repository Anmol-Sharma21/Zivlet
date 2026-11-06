import Foundation
import ZivletCore

/// How a part of a PDF is encrypted.
public enum PDFCipher: String, Sendable, Codable, Equatable {
    case rc4, aes128, aes256, identity, unknown
}

/// A document's encryption as far as Zivlet can tell.
public enum PDFEncryption: Sendable, Codable, Equatable {
    case none
    /// The Standard handler: its revision (R), version (V) and the cipher of streams, strings and embedded files.
    case standard(revision: Int, version: Int, streams: PDFCipher, strings: PDFCipher, files: PDFCipher)
    /// A handler other than the Standard one (`/Adobe.PubSec` certificates, a vendor's own): it cannot be opened.
    case publicKey
    /// The Standard handler at a revision or version qpdf cannot read: it cannot be opened.
    case unknown
}

/// Which password opened the document.
public enum PDFPasswordMatch: String, Sendable, Codable, Equatable {
    /// Not encrypted, or not opened.
    case none
    case user
    case owner
    /// The password is both (a file whose owner and user passwords are the same).
    case both

    /// The owner password matched, so restrictions do not apply.
    public var includesOwner: Bool { self == .owner || self == .both }

    public init(owner: Bool, user: Bool) {
        switch (owner, user) {
        case (true, true): self = .both
        case (true, false): self = .owner
        case (false, true): self = .user
        case (false, false): self = .none
        }
    }
}

/// What a PDF holds (P2-105, FR-107, D-M7-18), so a tool can decide before it writes anything. The worker reads it
/// with the qpdf library (`EnginePDF.PDFInspector`); the app only reads the answer, so this value sits here.
///
/// A file that is locked and got no right password is "shut": only `encryption`, `permissions` (empty for a handler
/// Zivlet cannot read), `pdfVersion` and `warningCount` are known, and the rest reads 0 or false.
public struct PDFPreflight: Sendable, Codable, Equatable {
    public let pageCount: Int
    public let encryption: PDFEncryption
    public let permissions: PDFPermissions
    /// No password is needed to read it: not encrypted, or the empty user password works (a restrictions-only file).
    public let opensWithoutPassword: Bool
    /// Which password the given one is; for no password on a restrictions-only file, `.user`.
    public let matched: PDFPasswordMatch
    public let hasAcroForm: Bool
    public let fieldCount: Int
    /// Fields of type `/Sig`.
    public let signatureFieldCount: Int
    /// The catalog has a `/StructTreeRoot`.
    public let isTagged: Bool
    /// `/Names /EmbeddedFiles`, or a file attachment annotation on a page.
    public let hasEmbeddedFiles: Bool
    /// `/Names /JavaScript`, an `/OpenAction` that runs JavaScript, or any `/AA` on the catalog or a page.
    public let hasJavaScript: Bool
    public let isLinearized: Bool
    /// The header's version, for example "1.7".
    public let pdfVersion: String
    /// Warnings qpdf counted while reading (shown nowhere).
    public let warningCount: Int

    public init(
        pageCount: Int, encryption: PDFEncryption = .none, permissions: PDFPermissions = .all,
        opensWithoutPassword: Bool = true, matched: PDFPasswordMatch = .none, hasAcroForm: Bool = false,
        fieldCount: Int = 0, signatureFieldCount: Int = 0, isTagged: Bool = false, hasEmbeddedFiles: Bool = false,
        hasJavaScript: Bool = false, isLinearized: Bool = false, pdfVersion: String = "", warningCount: Int = 0
    ) {
        self.pageCount = pageCount
        self.encryption = encryption
        self.permissions = permissions
        self.opensWithoutPassword = opensWithoutPassword
        self.matched = matched
        self.hasAcroForm = hasAcroForm
        self.fieldCount = fieldCount
        self.signatureFieldCount = signatureFieldCount
        self.isTagged = isTagged
        self.hasEmbeddedFiles = hasEmbeddedFiles
        self.hasJavaScript = hasJavaScript
        self.isLinearized = isLinearized
        self.pdfVersion = pdfVersion
        self.warningCount = warningCount
    }

    /// Locked and not opened: what is behind the password is unknown.
    public var isShut: Bool { !opensWithoutPassword && matched == .none }
}

/// Reads a dropped PDF's pre-flight without a password (plan 20f E9). The worker hosts the qpdf-backed reader
/// (`EnginePDF`); the worker's service sees only this protocol, so it never links qpdf itself.
public protocol PDFInspecting: Sendable {
    func preflight(_ file: URL) async -> Result<PDFPreflight, JobError>
}

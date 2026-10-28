import CZivletPDF

/// How a part of a PDF is encrypted.
public enum PDFCipher: Sendable, Equatable {
    case rc4, aes128, aes256, identity, unknown

    init?(_ method: zv_pdf_method) {
        switch method {
        case ZV_PDF_METHOD_NONE: return nil
        case ZV_PDF_METHOD_RC4: self = .rc4
        case ZV_PDF_METHOD_AES128: self = .aes128
        case ZV_PDF_METHOD_AES256: self = .aes256
        case ZV_PDF_METHOD_IDENTITY: self = .identity
        default: self = .unknown
        }
    }
}

/// A document's encryption as qpdf reads it: the Standard handler's revision (R), version (V) and stream cipher.
public enum PDFEncryption: Sendable, Equatable {
    case none
    case standard(revision: Int, version: Int, streams: PDFCipher)
}

/// Which password opened the document.
public enum PDFPasswordMatch: Sendable, Equatable {
    /// Not encrypted, or opened with neither password (qpdf refuses that, so this means "not encrypted").
    case none
    case user
    case owner
    /// The password is both (a file whose owner and user passwords are the same).
    case both

    /// The owner password matched, so restrictions do not apply.
    public var includesOwner: Bool { self == .owner || self == .both }

    init(owner: Bool, user: Bool) {
        switch (owner, user) {
        case (true, true): self = .both
        case (true, false): self = .owner
        case (false, true): self = .user
        case (false, false): self = .none
        }
    }
}

/// What `QPDFDocumentReader.inspect` learns (plan 20d C4); stream D's pre-flight builds on it.
public struct QPDFDocumentInfo: Sendable, Equatable {
    public let pageCount: Int
    public let encryption: PDFEncryption
    public let matched: PDFPasswordMatch
    /// The /P value of an encrypted file; nil when it is not encrypted.
    public let permissions: Int32?
    /// Warnings qpdf counted while reading (shown nowhere).
    public let warningCount: Int

    init(_ info: zv_pdf_info) {
        pageCount = Int(info.page_count)
        warningCount = Int(info.warning_count)
        guard info.encrypted != 0 else {
            encryption = .none
            matched = .none
            permissions = nil
            return
        }
        encryption = .standard(
            revision: Int(info.revision), version: Int(info.version), streams: PDFCipher(info.streams) ?? .unknown)
        matched = PDFPasswordMatch(owner: info.owner_matched != 0, user: info.user_matched != 0)
        permissions = info.permissions
    }
}

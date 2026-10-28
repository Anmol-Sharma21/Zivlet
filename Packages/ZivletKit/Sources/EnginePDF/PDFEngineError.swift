import CZivletPDF

/// Why a qpdf call failed (plan 20d C4). The worker turns these into job errors with their own copy (stream E); none
/// of them carries a path, a password or qpdf's message text.
public enum PDFEngineError: Error, Sendable, Equatable {
    /// The password given, or no password, opens the file neither as user nor as owner.
    case wrongPassword
    /// The file is not a readable PDF, or the check found errors in it.
    case damaged
    /// The file uses a security handler other than the Standard one (certificates, a vendor's own).
    case unsupportedEncryption
    /// The file exceeds a page or parser limit.
    case limit
    /// The file could not be read, or the output could not be written.
    case io
    /// Something is already at the output path; nothing is ever overwritten.
    case outputExists
    /// The password holds a NUL byte, which qpdf cannot take.
    case unusablePassword
    /// A fault inside the shim or qpdf.
    case internalFailure

    /// The error for a shim status, or nil for success.
    init?(status: zv_pdf_status) {
        switch status {
        case ZV_PDF_OK: return nil
        case ZV_PDF_WRONG_PASSWORD: self = .wrongPassword
        case ZV_PDF_DAMAGED: self = .damaged
        case ZV_PDF_UNSUPPORTED_ENCRYPTION: self = .unsupportedEncryption
        case ZV_PDF_LIMIT: self = .limit
        case ZV_PDF_IO: self = .io
        case ZV_PDF_OUTPUT_EXISTS: self = .outputExists
        case ZV_PDF_UNUSABLE_PASSWORD: self = .unusablePassword
        default: self = .internalFailure
        }
    }

    /// Throws the error for `status` unless it is success.
    static func check(_ status: zv_pdf_status) throws(PDFEngineError) {
        if let error = PDFEngineError(status: status) { throw error }
    }
}

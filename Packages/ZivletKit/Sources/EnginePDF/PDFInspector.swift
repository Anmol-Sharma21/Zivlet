import CZivletPDF
import Foundation
import ZivletCore
import ZivletEngineKit

/// P2-105's pre-flight (plan 20e D1, D-M7-18): the facts of `qpdf --json`, read through the library, so no recovered
/// password is ever printed. Only the worker links it (D-M7-16). Never prints, never logs.
public enum PDFInspector {
    /// What `url` holds, opened with `password`. A locked file with no password (or an empty one) and a file whose
    /// handler cannot be read are answers, not errors: their `PDFPreflight` is shut and tells the encryption, which
    /// is how the app picks between Lock and Unlock. A password that is wrong throws `.wrongPassword`.
    public static func inspect(
        _ url: URL, password: JobSecret?, limits: QPDFLimits = .standard
    ) throws(PDFEngineError) -> PDFPreflight {
        var shimLimits = limits.shimValue
        var info = zv_pdf_info()
        let status = ShimCall.status(url, password) { path, bytes in
            zv_pdf_inspect(path, bytes.pointer, bytes.count, &shimLimits, &info)
        }
        switch status {
        case ZV_PDF_UNSUPPORTED_ENCRYPTION: break
        case ZV_PDF_WRONG_PASSWORD where password?.isEmpty ?? true: break
        default: try PDFEngineError.check(status)
        }
        return PDFPreflight(info)
    }
}

extension PDFCipher {
    fileprivate init(_ method: zv_pdf_method) {
        switch method {
        case ZV_PDF_METHOD_RC4: self = .rc4
        case ZV_PDF_METHOD_AES128: self = .aes128
        case ZV_PDF_METHOD_AES256: self = .aes256
        case ZV_PDF_METHOD_IDENTITY: self = .identity
        default: self = .unknown
        }
    }
}

extension PDFEncryption {
    fileprivate init(_ info: zv_pdf_info) {
        switch info.handler {
        case ZV_PDF_HANDLER_NONE: self = .none
        case ZV_PDF_HANDLER_STANDARD:
            self = .standard(
                revision: Int(info.revision), version: Int(info.version), streams: PDFCipher(info.streams),
                strings: PDFCipher(info.strings), files: PDFCipher(info.files))
        case ZV_PDF_HANDLER_OTHER: self = .publicKey
        default: self = .unknown
        }
    }
}

extension PDFPreflight {
    fileprivate init(_ info: zv_pdf_info) {
        self.init(
            pageCount: Int(info.page_count), encryption: PDFEncryption(info),
            permissions: PDFPermissions(rawValue: info.allowed), opensWithoutPassword: info.opens_without_password != 0,
            matched: PDFPasswordMatch(owner: info.owner_matched != 0, user: info.user_matched != 0),
            hasAcroForm: info.has_acroform != 0, fieldCount: Int(info.field_count),
            signatureFieldCount: Int(info.signature_field_count), isTagged: info.is_tagged != 0,
            hasEmbeddedFiles: info.has_embedded_files != 0, hasJavaScript: info.has_javascript != 0,
            isLinearized: info.is_linearized != 0, pdfVersion: "\(info.pdf_major).\(info.pdf_minor)",
            warningCount: Int(info.warning_count))
    }
}

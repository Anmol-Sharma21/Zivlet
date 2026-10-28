import CZivletPDF
import Foundation
import ZivletCore

/// Lends a URL's path and a secret's bytes to one shim call (plan 20d C4). The bytes are the secret's own buffer;
/// no Swift copy of them is made.
enum ShimCall {
    typealias Bytes = (pointer: UnsafePointer<UInt8>?, count: Int)

    /// Throws the error of the status `body` returns for the URL's path and the secret's bytes.
    static func run(
        _ url: URL, _ secret: JobSecret?, _ body: (UnsafePointer<CChar>, Bytes) -> zv_pdf_status
    ) throws(PDFEngineError) {
        try PDFEngineError.check(status(url, secret, body))
    }

    /// The status `body` returns for the URL's path and the secret's bytes.
    static func status(
        _ url: URL, _ secret: JobSecret?, _ body: (UnsafePointer<CChar>, Bytes) -> zv_pdf_status
    ) -> zv_pdf_status {
        url.withUnsafeFileSystemRepresentation { path -> zv_pdf_status in
            guard let path else { return ZV_PDF_IO }
            return withBytes(of: secret) { bytes in body(path, bytes) }
        }
    }

    /// `body` with the secret's bytes, or with no bytes when there is no secret.
    static func withBytes<Result>(of secret: JobSecret?, _ body: (Bytes) -> Result) -> Result {
        guard let secret else { return body((nil, 0)) }
        return secret.withBytes { raw in body((raw.assumingMemoryBound(to: UInt8.self).baseAddress, raw.count)) }
    }
}

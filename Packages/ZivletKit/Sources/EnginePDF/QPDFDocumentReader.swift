import CZivletPDF
import Foundation
import ZivletCore

/// Reads PDFs through the shim (plan 20d C4); only the worker links it (D-M7-16). Never prints, never logs.
public enum QPDFDocumentReader {
    /// Opens `url` with `password` (nil: none) and says what it is.
    public static func inspect(
        _ url: URL, password: JobSecret?, limits: QPDFLimits = .standard
    ) throws(PDFEngineError) -> QPDFDocumentInfo {
        var shimLimits = limits.shimValue
        var info = zv_pdf_info()
        try ShimCall.run(url, password) { path, bytes in
            zv_pdf_inspect(path, bytes.pointer, bytes.count, &shimLimits, &info)
        }
        return QPDFDocumentInfo(info)
    }

    /// Reads every object, decodes every stream and parses every page; returns the warning count, or throws
    /// `.damaged` when the document has errors (qpdf's --check without its output, D-M7-16).
    @discardableResult
    public static func check(
        _ url: URL, password: JobSecret?, limits: QPDFLimits = .standard
    ) throws(PDFEngineError) -> Int {
        var shimLimits = limits.shimValue
        var warnings: UInt32 = 0
        try ShimCall.run(url, password) { path, bytes in
            zv_pdf_check(path, bytes.pointer, bytes.count, &shimLimits, &warnings)
        }
        return Int(warnings)
    }
}

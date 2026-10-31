import CZivletPDF
import ZivletEngineKit

/// The limits the shim applies before it reads a document (plan 20d C4); `standard` holds `PDFLimits`' values, the
/// policy of D-M7-18.
public struct QPDFLimits: Sendable, Equatable {
    /// At most this many pages for a structural tool (lock, unlock, change, pre-flight); 0: no limit.
    public let maxPages: UInt32
    public let maxNesting: UInt32
    public let maxContainerSize: UInt32
    public let maxContainerSizeDamaged: UInt32
    public let maxErrors: UInt32
    public let maxStreamFilters: UInt32
    /// A write refuses a file with more warnings than this; reading it is still allowed.
    public let maxWarnings: UInt32

    public init(
        maxPages: UInt32 = PDFLimits.maxStructuralPages, maxNesting: UInt32 = PDFLimits.maxParserNesting,
        maxContainerSize: UInt32 = PDFLimits.maxContainerSize,
        maxContainerSizeDamaged: UInt32 = PDFLimits.maxContainerSizeDamaged,
        maxErrors: UInt32 = PDFLimits.maxParserErrors, maxStreamFilters: UInt32 = PDFLimits.maxStreamFilters,
        maxWarnings: UInt32 = PDFLimits.maxWarnings
    ) {
        self.maxPages = maxPages
        self.maxNesting = maxNesting
        self.maxContainerSize = maxContainerSize
        self.maxContainerSizeDamaged = maxContainerSizeDamaged
        self.maxErrors = maxErrors
        self.maxStreamFilters = maxStreamFilters
        self.maxWarnings = maxWarnings
    }

    /// D-M7-18's values.
    public static let standard = QPDFLimits()

    var shimValue: zv_pdf_limits {
        zv_pdf_limits(
            max_pages: maxPages, max_nesting: maxNesting, max_container_size: maxContainerSize,
            max_container_size_damaged: maxContainerSizeDamaged, max_errors: maxErrors,
            max_stream_filters: maxStreamFilters, max_warnings: maxWarnings)
    }
}

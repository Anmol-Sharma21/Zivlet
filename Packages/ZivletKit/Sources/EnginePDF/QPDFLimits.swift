import CZivletPDF

/// The limits the shim applies before it reads a document (plan 20d C4, the values of D-M7-18). Stream D's
/// `PDFLimits` adds the input size and the policy around them.
public struct QPDFLimits: Sendable, Equatable {
    /// At most this many pages for a structural tool (lock, unlock, change, pre-flight).
    public let maxPages: UInt32
    public let maxNesting: UInt32
    public let maxContainerSize: UInt32
    public let maxContainerSizeDamaged: UInt32
    public let maxErrors: UInt32
    public let maxStreamFilters: UInt32

    public init(
        maxPages: UInt32 = 10_000, maxNesting: UInt32 = 500, maxContainerSize: UInt32 = 1_000_000,
        maxContainerSizeDamaged: UInt32 = 50_000, maxErrors: UInt32 = 1_000, maxStreamFilters: UInt32 = 25
    ) {
        self.maxPages = maxPages
        self.maxNesting = maxNesting
        self.maxContainerSize = maxContainerSize
        self.maxContainerSizeDamaged = maxContainerSizeDamaged
        self.maxErrors = maxErrors
        self.maxStreamFilters = maxStreamFilters
    }

    /// D-M7-18's values.
    public static let standard = QPDFLimits()

    var shimValue: zv_pdf_limits {
        zv_pdf_limits(
            max_pages: maxPages, max_nesting: maxNesting, max_container_size: maxContainerSize,
            max_container_size_damaged: maxContainerSizeDamaged, max_errors: maxErrors,
            max_stream_filters: maxStreamFilters)
    }
}

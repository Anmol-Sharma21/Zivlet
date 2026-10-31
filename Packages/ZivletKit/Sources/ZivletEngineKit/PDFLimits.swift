import Darwin
import Foundation
import ZivletCore

/// The limits on a PDF Zivlet will touch (P2-105, D-M7-18), so a hostile file costs a refusal, not the worker. The app
/// checks the size first, from the drop; the worker checks it again and sets the rest on qpdf before each document.
public enum PDFLimits {
    /// 512 MB as Finder counts it, so the refusal's words match what a person sees.
    public static let maxInputBytes: Int64 = 512_000_000
    /// For tools that rewrite structure and never draw a page: lock, unlock, change password, pre-flight.
    public static let maxStructuralPages: UInt32 = 10_000
    /// For tools that draw every page: Copy Text, Read QR.
    public static let maxRenderingPages = 500
    public static let maxParserNesting: UInt32 = 500
    public static let maxContainerSize: UInt32 = 1_000_000
    public static let maxContainerSizeDamaged: UInt32 = 50_000
    public static let maxParserErrors: UInt32 = 1_000
    public static let maxStreamFilters: UInt32 = 25
    /// Past this many warnings a file counts as damaged for a write; pre-flight still reads and reports it.
    public static let maxWarnings: UInt32 = 100

    /// What the watchdog gives a blocking qpdf call: this much, plus a second per `watchdogBytesPerSecond`.
    static let watchdogBase = Duration.seconds(30)
    static let watchdogBytesPerSecond: Int64 = 10_000_000

    public static func allows(inputBytes: Int64) -> Bool { inputBytes <= maxInputBytes }

    /// The size where the file lies now; a file that cannot be measured is left for the open to report.
    public static func allows(fileAt url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) != 0 || allows(inputBytes: Int64(info.st_size))
    }

    public static func check(inputBytes: Int64) throws(JobError) {
        guard allows(inputBytes: inputBytes) else { throw .unsupportedInput(.pdfTooLarge) }
    }

    public static func check(fileAt url: URL) throws(JobError) {
        guard allows(fileAt: url) else { throw .unsupportedInput(.pdfTooLarge) }
    }

    /// 30 s, plus 1 s per 10 MB of input.
    public static func watchdogBudget(inputBytes: Int64) -> Duration {
        let bytesPerMillisecond = watchdogBytesPerSecond / 1_000
        return watchdogBase + .milliseconds(max(0, inputBytes) / bytesPerMillisecond)
    }
}

import EnginePDF
import EngineTestSupport
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

/// P2-105's budget (FR-107): pre-flight reads a 100-page PDF within 50 ms, judged by `make timing` below the load limit
/// (D-M7-3). The slowest case is judged too: an AES-256 file with its password opens twice, the second time to learn
/// whether it needs one, and each open runs the R6 key derivation. The shim runs as a debug build here and qpdf as a
/// release one. The file at the page limit is printed, not judged: no budget names it.
@Suite("PDF pre-flight wall time (FR-107)", .enabled(if: TimingGate.isEnabled()), .serialized)
struct PreflightTiming {
    static let budgetMilliseconds = 50
    static let pages = 100
    static let samples = 20

    private static func inspect(_ url: URL, password: JobSecret? = nil) throws -> Duration {
        let clock = ContinuousClock()
        var facts: PDFPreflight?
        let elapsed = try clock.measure { facts = try PDFInspector.inspect(url, password: password) }
        #expect(facts != nil)
        return elapsed
    }

    /// `label`'s p95 over `samples` reads, reported and judged.
    private static func judge(_ label: String, _ url: URL, password: JobSecret? = nil) throws {
        let samples = try (0..<Self.samples).map { _ in try inspect(url, password: password) }
        let p95 = try Durations(samples).percentile(95)
        TimingGate.report("\(label) p95 \(TimingGate.milliseconds(p95)) of \(budgetMilliseconds) ms")
        #expect(p95 <= .milliseconds(budgetMilliseconds))
    }

    @Test func aHundredPagePDFIsReadWithinItsBudget() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.plain(in: dir.url, name: "hundred.pdf", pages: Self.pages)

        try Self.judge("preflight \(Self.pages) pages", url)
    }

    @Test func aHundredPageAES256PDFWithItsPasswordIsReadWithinItsBudget() throws {
        let dir = try TempDir()
        let plain = try PDFFixtures.plain(in: dir.url, name: "hundred.pdf", pages: Self.pages)
        let locked = dir.url.appending(path: "locked.pdf")
        let password = JobSecret(utf8: "zv-timing-" + UUID().uuidString)
        let mode = QPDFWriterBridge.Mode.encryptR6(R6Parameters(user: password, owner: password))
        try QPDFWriterBridge.write(plain, password: nil, mode: mode, to: locked)

        try Self.judge("preflight \(Self.pages) pages, AES-256 with its password", locked, password: password)
    }

    @Test func theFileAtThePageLimitIsMeasuredAndNotJudged() throws {
        let dir = try TempDir()
        let pages = Int(PDFLimits.maxStructuralPages)
        let url = try PDFFixtures.manyPages(in: dir.url, name: "limit.pdf", pages: pages)

        let elapsed = try Self.inspect(url)

        TimingGate.report("preflight \(pages) pages \(TimingGate.milliseconds(elapsed)) (not judged)")
    }
}

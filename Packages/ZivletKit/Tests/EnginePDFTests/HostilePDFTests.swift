import EngineTestSupport
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// Files built to hurt a parser (plan 20e D2, D-M7-18), in our own bytes: each stops at its limit, and a write leaves
/// nothing behind.
@Suite("Hostile PDFs stop at a limit (D-M7-18)")
struct HostilePDFTests {
    private func nested(_ depth: Int) -> [String] {
        let open = String(repeating: "[", count: depth)
        let close = String(repeating: "]", count: depth)
        return PDFFixtures.objects(catalog: "/Deep \(open)\(close)")
    }

    private func filtered(_ count: Int) -> [String] {
        let filters = Array(repeating: "/FlateDecode", count: count).joined(separator: " ")
        return [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
            "<< /Length 0 /Filter [\(filters)] >>\nstream\n\nendstream",
        ]
    }

    /// One catalog array of `count` copies of `entry`.
    private func container(_ entry: String, count: Int) -> [String] {
        PDFFixtures.objects(catalog: "/Big [\(String(repeating: entry + " ", count: count))]")
    }

    /// `count` parser errors, far enough apart that qpdf does not give up on five close together.
    private func parserErrors(_ count: Int) -> [String] {
        container("{ /a /a /a /a /a /a", count: count)
    }

    private func expectRefused(_ url: URL, _ error: PDFEngineError, in dir: TempDir) {
        let output = dir.url.appending(path: "out-\(UUID().uuidString).pdf")
        #expect(throws: error) { try QPDFWriterBridge.write(url, password: nil, mode: .preserve, to: output) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func arraysNestedPastTheLimitAreRefused() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.raw(in: dir.url, name: "deep.pdf", objects: nested(600))

        #expect(throws: PDFEngineError.limit) { try PDFInspector.inspect(url, password: nil) }
        expectRefused(url, .limit, in: dir)
    }

    /// qpdf's own default is 499, so a file at 500 shows that the shim's value is the one in force.
    @Test func arraysNestedToExactlyTheLimitAreReadAndOneMoreIsNot() throws {
        let dir = try TempDir()
        let depth = Int(PDFLimits.maxParserNesting)
        let at = try PDFFixtures.raw(in: dir.url, name: "at.pdf", objects: nested(depth))
        let over = try PDFFixtures.raw(in: dir.url, name: "over.pdf", objects: nested(depth + 1))

        #expect(try PDFInspector.inspect(at, password: nil).pageCount == 1)
        #expect(throws: PDFEngineError.limit) { try PDFInspector.inspect(over, password: nil) }
        #expect(throws: PDFEngineError.limit) {
            try PDFInspector.inspect(at, password: nil, limits: QPDFLimits(maxNesting: PDFLimits.maxParserNesting - 1))
        }
    }

    /// qpdf sets no limit of its own here.
    @Test func aContainerOfExactlyTheLimitIsReadAndOneMoreEntryIsNot() throws {
        let dir = try TempDir()
        let size = Int(PDFLimits.maxContainerSize)
        let at = try PDFFixtures.raw(in: dir.url, name: "at.pdf", objects: container("/a", count: size))
        let over = try PDFFixtures.raw(in: dir.url, name: "over.pdf", objects: container("/a", count: size + 1))

        #expect(try PDFInspector.inspect(at, password: nil).pageCount == 1)
        #expect(throws: PDFEngineError.limit) { try PDFInspector.inspect(over, password: nil) }
        expectRefused(over, .limit, in: dir)
        #expect(throws: PDFEngineError.limit) {
            try PDFInspector.inspect(
                at, password: nil, limits: QPDFLimits(maxContainerSize: PDFLimits.maxContainerSize - 1))
        }
    }

    /// qpdf's own default is 5,000, so a file of 50,000 shows that the shim's value is the one in force.
    @Test func aDamagedFileHasTheSmallerContainerLimit() throws {
        let dir = try TempDir()
        let size = Int(PDFLimits.maxContainerSizeDamaged)
        let at = try PDFFixtures.brokenCrossReference(
            in: dir.url, name: "at.pdf", objects: container("/a", count: size))
        let over = try PDFFixtures.brokenCrossReference(
            in: dir.url, name: "over.pdf", objects: container("/a", count: size + 1))

        #expect(try PDFInspector.inspect(at, password: nil).pageCount == 1)
        #expect(throws: PDFEngineError.limit) { try PDFInspector.inspect(over, password: nil) }
        #expect(throws: PDFEngineError.limit) {
            try PDFInspector.inspect(
                at, password: nil, limits: QPDFLimits(maxContainerSizeDamaged: PDFLimits.maxContainerSizeDamaged - 1))
        }
    }

    /// qpdf's own default is 15. Its counter stops the read on the error that reaches the limit.
    @Test func parserErrorsStopAtTheLimit() throws {
        let dir = try TempDir()
        let limit = Int(PDFLimits.maxParserErrors)
        let under = try PDFFixtures.raw(in: dir.url, name: "under.pdf", objects: parserErrors(limit - 1))
        let at = try PDFFixtures.raw(in: dir.url, name: "at.pdf", objects: parserErrors(limit))

        #expect(try PDFInspector.inspect(under, password: nil).pageCount == 1)
        #expect(throws: PDFEngineError.limit) { try PDFInspector.inspect(at, password: nil) }
        #expect(throws: PDFEngineError.limit) {
            try PDFInspector.inspect(under, password: nil, limits: QPDFLimits(maxErrors: PDFLimits.maxParserErrors - 1))
        }
    }

    /// Our value equals qpdf's default, so only a lower one shows that the shim's value is the one in force.
    @Test func theFilterLimitIsTheShimsOwn() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.raw(in: dir.url, name: "filters.pdf", objects: filtered(6))

        #expect(throws: PDFEngineError.limit) {
            try QPDFDocumentReader.check(url, password: nil, limits: QPDFLimits(maxStreamFilters: 5))
        }
    }

    /// qpdf 12.4.2 counts names, strings, reals and booleans towards a container's size, not these. The limit cannot
    /// hold them, so the watchdog's memory ceiling does. If an upgrade starts counting them, this says so.
    @Test(arguments: ["0", "null", "4 0 R"])
    func theContainerLimitDoesNotCount(entry: String) throws {
        let dir = try TempDir()
        let count = Int(PDFLimits.maxContainerSize) + 1
        let url = try PDFFixtures.raw(in: dir.url, name: "big.pdf", objects: container(entry, count: count))

        #expect(try PDFInspector.inspect(url, password: nil).pageCount == 1)
    }

    @Test func thirtyChainedFiltersAreRefused() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.raw(in: dir.url, name: "filters.pdf", objects: filtered(30))

        #expect(throws: PDFEngineError.limit) { try QPDFDocumentReader.check(url, password: nil) }
        expectRefused(url, .limit, in: dir)
    }

    @Test func oneFilterPastTheLimitIsRefusedAndTheLimitItselfIsNot() throws {
        let dir = try TempDir()
        let over = try PDFFixtures.raw(in: dir.url, name: "over.pdf", objects: filtered(26))
        let at = try PDFFixtures.raw(in: dir.url, name: "at.pdf", objects: filtered(25))

        #expect(throws: PDFEngineError.limit) { try QPDFDocumentReader.check(over, password: nil) }
        do {
            try QPDFDocumentReader.check(at, password: nil)
        } catch {
            #expect(error != .limit)
        }
    }

    @Test func aTruncatedFileThatKeptItsObjectsIsReadWithACountOfWarnings() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.raw(in: dir.url, name: "cut.pdf", objects: PDFFixtures.onePageObjects)
        let bytes = try Data(contentsOf: url)
        let tail = try #require(bytes.range(of: Data("xref\n".utf8)))
        try bytes[..<tail.lowerBound].write(to: url)

        let facts = try PDFInspector.inspect(url, password: nil)

        #expect(facts.pageCount == 1)
        #expect(facts.warningCount > 0)
    }

    @Test func aTruncatedFileThatLostItsCatalogIsDamaged() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.plain(in: dir.url)
        let bytes = try Data(contentsOf: url)
        try bytes.prefix(bytes.count / 3).write(to: url)

        #expect(throws: PDFEngineError.damaged) { try PDFInspector.inspect(url, password: nil) }
        expectRefused(url, .damaged, in: dir)
    }

    @Test func aWarningPastTheLimitIsDamagedForAWriteButPreflightStillReportsIt() throws {
        let dir = try TempDir()
        let over = PDFLimits.maxWarnings + 1
        let url = try PDFFixtures.oneWarningPerPage(in: dir.url, name: "worn.pdf", pages: Int(over))

        let facts = try PDFInspector.inspect(url, password: nil)

        #expect(facts.warningCount == Int(over))
        #expect(facts.pageCount == Int(over))
        expectRefused(url, .damaged, in: dir)
    }

    @Test func exactlyTheLimitOfWarningsStillWrites() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.oneWarningPerPage(in: dir.url, name: "worn.pdf", pages: Int(PDFLimits.maxWarnings))
        let output = dir.url.appending(path: "out.pdf")

        try QPDFWriterBridge.write(url, password: nil, mode: .preserve, to: output)

        #expect(try PDFInspector.inspect(output, password: nil).pageCount == Int(PDFLimits.maxWarnings))
    }

    @Test func tenThousandPagesAreRead() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.manyPages(in: dir.url, name: "long.pdf", pages: Int(PDFLimits.maxStructuralPages))

        #expect(try PDFInspector.inspect(url, password: nil).pageCount == Int(PDFLimits.maxStructuralPages))
    }

    @Test func tenThousandAndOnePagesAreRefusedBeforeAnyWrite() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.manyPages(in: dir.url, name: "long.pdf", pages: Int(PDFLimits.maxStructuralPages) + 1)

        #expect(throws: PDFEngineError.limit) { try PDFInspector.inspect(url, password: nil) }
        expectRefused(url, .limit, in: dir)
    }

    @Test func theStandardLimitsAreTheDecisionsValues() {
        let limits = QPDFLimits.standard

        #expect(limits.maxPages == PDFLimits.maxStructuralPages)
        #expect(limits.maxNesting == PDFLimits.maxParserNesting)
        #expect(limits.maxContainerSize == PDFLimits.maxContainerSize)
        #expect(limits.maxContainerSizeDamaged == PDFLimits.maxContainerSizeDamaged)
        #expect(limits.maxErrors == PDFLimits.maxParserErrors)
        #expect(limits.maxStreamFilters == PDFLimits.maxStreamFilters)
        #expect(limits.maxWarnings == PDFLimits.maxWarnings)
    }
}

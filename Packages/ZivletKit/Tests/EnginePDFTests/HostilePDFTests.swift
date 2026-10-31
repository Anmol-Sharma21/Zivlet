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

    @Test func arraysNestedInsideTheLimitAreRead() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.raw(in: dir.url, name: "deep.pdf", objects: nested(450))

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

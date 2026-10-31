import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@Suite("Limits for hostile PDFs (D-M7-18)")
struct PDFLimitsTests {
    @Test func theValuesAreTheDecision() {
        #expect(PDFLimits.maxInputBytes == 512_000_000)
        #expect(PDFLimits.maxStructuralPages == 10_000)
        #expect(PDFLimits.maxRenderingPages == 500)
        #expect(PDFLimits.maxParserNesting == 500)
        #expect(PDFLimits.maxContainerSize == 1_000_000)
        #expect(PDFLimits.maxContainerSizeDamaged == 50_000)
        #expect(PDFLimits.maxParserErrors == 1_000)
        #expect(PDFLimits.maxStreamFilters == 25)
        #expect(PDFLimits.maxWarnings == 100)
        #expect(PDFLimits.maxWorkerFootprint == 3_000_000_000)
        #expect(PDFLimits.memoryPollInterval == .milliseconds(100))
    }

    @Test func anInputOfExactly512MBPasses() throws {
        try PDFLimits.check(inputBytes: 512_000_000)
        #expect(PDFLimits.allows(inputBytes: 512_000_000))
    }

    @Test func oneByteMoreIsRefused() {
        #expect(throws: JobError.unsupportedInput(.pdfTooLarge)) {
            try PDFLimits.check(inputBytes: 512_000_001)
        }
        #expect(!PDFLimits.allows(inputBytes: 512_000_001))
    }

    @Test(arguments: [
        (Int64(0), Duration.seconds(30)),
        (100_000_000, .seconds(40)),
        (512_000_000, .milliseconds(81_200)),
    ])
    func theWatchdogGivesThirtySecondsAndOnePer10MB(bytes: Int64, budget: Duration) {
        #expect(PDFLimits.watchdogBudget(inputBytes: bytes) == budget)
    }

    @Test func aNegativeSizeGetsTheBaseBudget() {
        #expect(PDFLimits.watchdogBudget(inputBytes: -1) == .seconds(30))
    }

    @Test func aFileIsMeasuredWhereItLies() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "zivlet-limits-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
        // Sparse: the size is set without writing the bytes.
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(PDFLimits.maxInputBytes))
        #expect(PDFLimits.allows(fileAt: file))

        try handle.truncate(atOffset: UInt64(PDFLimits.maxInputBytes) + 1)
        try handle.close()

        #expect(!PDFLimits.allows(fileAt: file))
        #expect(throws: JobError.unsupportedInput(.pdfTooLarge)) { try PDFLimits.check(fileAt: file) }
    }

    @Test func aMissingFileIsLeftForTheOpenToReport() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "zivlet-gone-\(UUID().uuidString).pdf")

        #expect(PDFLimits.allows(fileAt: missing))
        try PDFLimits.check(fileAt: missing)
    }
}

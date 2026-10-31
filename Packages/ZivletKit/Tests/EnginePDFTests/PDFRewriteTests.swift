import EngineTestSupport
import Foundation
import PDFKit
import Synchronization
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// The qpdf-first rule (plan 20e D4, D-PDF-3): a PDF that PDFKit or Quartz wrote is rewritten and checked by qpdf.
@Suite("Quartz and PDFKit output is rewritten by qpdf (D-PDF-3)")
struct PDFRewriteTests {
    /// The bytes qpdf writes on a PDF's second line; Quartz writes others.
    static let qpdfMarker = Data([0x25, 0xBF, 0xF7, 0xA2, 0xFE])

    private func folder(_ dir: TempDir) throws -> URL { try dir.folder(".zivlet-\(JobID())") }

    @Test func aQuartzFileIsRewrittenInPlaceAndNothingElseIsLeft() throws {
        let dir = try TempDir()
        let staging = try folder(dir)
        let staged = try PDFFixtures.plain(in: staging, name: "staged.pdf")
        let quartz = try Data(contentsOf: staged)

        let size = try PDFRewrite.normalise(staged: staged)

        let rewritten = try Data(contentsOf: staged)
        #expect(rewritten != quartz)
        #expect(quartz.range(of: Self.qpdfMarker) == nil)
        #expect(rewritten.range(of: Self.qpdfMarker) != nil)
        #expect(size == Int64(rewritten.count))
        #expect(PDFDocument(url: staged)?.pageCount == 2)
        #expect(try QPDFDocumentReader.check(staged, password: nil) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path) == ["staged.pdf"])
    }

    @Test func aFileQPDFCannotReadIsLeftAsItWasWithNothingBesideIt() throws {
        let dir = try TempDir()
        let staging = try folder(dir)
        let staged = staging.appending(path: "staged.pdf")
        try Data("These words are not a PDF.".utf8).write(to: staged)

        #expect(throws: PDFEngineError.damaged) { try PDFRewrite.normalise(staged: staged) }

        #expect(try String(contentsOf: staged, encoding: .utf8) == "These words are not a PDF.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path) == ["staged.pdf"])
    }

    @Test func aRewriteThatFailsItsCheckLeavesTheFileAsItWas() throws {
        let dir = try TempDir()
        let staging = try folder(dir)
        let noPages = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [] /Count 0 >>"]
        let staged = try PDFFixtures.raw(in: staging, name: "staged.pdf", objects: noPages)
        let before = try Data(contentsOf: staged)

        #expect(throws: PDFEngineError.damaged) { try PDFRewrite.normalise(staged: staged) }

        #expect(try Data(contentsOf: staged) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path) == ["staged.pdf"])
    }

    /// A crash mid-rewrite leaves its work in the staging folder, and the retry comes back to the same folder.
    @Test func whatACrashedRewriteLeftDoesNotStopTheRetry() throws {
        let dir = try TempDir()
        let staging = try folder(dir)
        let staged = try PDFFixtures.plain(in: staging, name: "staged.pdf")
        try Data("half a file".utf8).write(to: PDFRewrite.rewritePath(of: staged))

        _ = try PDFRewrite.normalise(staged: staged)

        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path) == ["staged.pdf"])
    }

    /// The limit on pages is for files people drop; a long TIFF makes a long PDF of Zivlet's own.
    @Test func thePageLimitDoesNotApplyToZivletsOwnOutput() throws {
        let dir = try TempDir()
        let staging = try folder(dir)
        let staged = try PDFFixtures.manyPages(
            in: staging, name: "staged.pdf", pages: Int(PDFLimits.maxStructuralPages) + 1)

        _ = try PDFRewrite.normalise(staged: staged)

        let unlimited = QPDFLimits(maxPages: 0)
        #expect(
            try PDFInspector.inspect(staged, password: nil, limits: unlimited).pageCount
                == Int(PDFLimits.maxStructuralPages) + 1)
    }
}

/// `PDFRewritingEngine` adds the rule to an engine that writes through Quartz, leaving everything else to it.
@Suite("An engine that writes through Quartz, with the rewrite added (D-PDF-3)")
struct PDFRewritingEngineTests {
    /// Writes a Quartz PDF, or a plain text "image", as its plan says.
    struct QuartzEngine: Engine {
        let id = EngineID.image

        func handles(_ pair: ConversionPair) -> Bool { pair.source == .png }
        func availability(of pair: ConversionPair) async -> RouteAvailability { .unavailable(["scripted"]) }
        func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
            throw .internalInvariant("scripted prepare")
        }
        func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
            StagedOutput(
                format: plan.outputFormat, url: plan.stagedFile, byteCount: 1, withdrawnNotes: [.alphaFlattened])
        }
        func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
            throw .verificationFailed("scripted verify")
        }
    }

    private func plan(_ staged: URL, format: FormatID) throws -> ExecutionPlan {
        try ExecutionPlan(
            engine: .image, stages: [.pdf(PDFStage(source: staged, encryption: .keep, pageCount: 1))],
            stageWeights: [1], lanes: [.cpu], outputFormat: format, stagedFile: staged)
    }

    @Test func aPDFOutputIsRewrittenAndItsSizeAndNotesAreTheFinalOnes() async throws {
        let dir = try TempDir()
        let staging = try dir.folder(".zivlet-\(JobID())")
        let staged = try PDFFixtures.plain(in: staging, name: "staged.pdf")
        let engine = PDFRewritingEngine(wrapping: QuartzEngine())

        let output = try await engine.execute(try plan(staged, format: .pdf), context: ExecutionContext())

        let bytes = try Data(contentsOf: staged)
        #expect(bytes.range(of: PDFRewriteTests.qpdfMarker) != nil)
        #expect(output.byteCount == Int64(bytes.count))
        #expect(output.withdrawnNotes == [.alphaFlattened])
    }

    @Test func anOutputThatIsNotAPDFIsLeftAlone() async throws {
        let dir = try TempDir()
        let staged = try dir.file("staged.png", "not touched")
        let engine = PDFRewritingEngine(wrapping: QuartzEngine())

        let output = try await engine.execute(try plan(staged, format: .png), context: ExecutionContext())

        #expect(output.byteCount == 1)
        #expect(try String(contentsOf: staged, encoding: .utf8) == "not touched")
    }

    @Test func aRewriteThatFailsMeansTheResultFailedItsChecks() async throws {
        let dir = try TempDir()
        let staging = try dir.folder(".zivlet-\(JobID())")
        let staged = staging.appending(path: "staged.pdf")
        try Data("not a PDF".utf8).write(to: staged)
        let engine = PDFRewritingEngine(wrapping: QuartzEngine())
        let plan = try plan(staged, format: .pdf)

        await #expect(throws: JobError.verificationFailed(PDFRewritingEngine.rewriteMessage)) {
            try await engine.execute(plan, context: ExecutionContext())
        }
    }

    @Test func everythingElseIsTheInnerEngines() async throws {
        let dir = try TempDir()
        let engine = PDFRewritingEngine(wrapping: QuartzEngine())
        let staged = try dir.file("staged.pdf")
        let plan = try plan(staged, format: .pdf)
        let pair = ConversionPair(source: .png, target: .pdf)

        #expect(engine.id == .image)
        #expect(engine.handles(pair))
        #expect(!engine.handles(ConversionPair(source: .jpg, target: .pdf)))
        #expect(await engine.availability(of: pair) == .unavailable(["scripted"]))
        let output = StagedOutput(format: .pdf, url: staged, byteCount: 1)
        await #expect(throws: JobError.verificationFailed("scripted verify")) {
            try await engine.verify(output, plan: plan)
        }
    }

    @Test func aRewriteTakesItsTurnUnderTheWatchdog() async throws {
        let recorder = PDFWatchdogTests.Recorder()
        let dir = try TempDir()
        let staging = try dir.folder(".zivlet-\(JobID())")
        let staged = try PDFFixtures.plain(in: staging, name: "staged.pdf")
        let engine = PDFRewritingEngine(wrapping: QuartzEngine(), watchdog: recorder.watchdog)

        _ = try await engine.execute(try plan(staged, format: .pdf), context: ExecutionContext())

        #expect(recorder.events.withLock { $0 }.count == 2)
    }
}

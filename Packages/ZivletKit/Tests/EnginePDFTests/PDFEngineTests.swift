import EngineTestSupport
import Foundation
import PDFKit
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// The worker's PDF engine (plan 20d C5, D-M7-16): it runs a plan's qpdf rewrite into the claimed staged file and
/// checks the result. The jobs that plan such rewrites (lock, unlock, change password) come with stream E.
@Suite("The PDF engine runs qpdf rewrites (P2-13)")
struct PDFEngineTests {
    /// A claimed staging folder with its empty staged file, as the runtime makes it.
    struct Rig {
        let dir: TempDir
        let staged: URL

        init() throws {
            dir = try TempDir(prefix: "zivlet-pdf-engine")
            let folder = try dir.folder(".zivlet-\(JobID())")
            staged = folder.appending(path: "staged.pdf")
            try Data().write(to: staged)
        }

        func plan(_ source: URL, encryption: PDFStage.Encryption = .keep, pageCount: Int = 2) throws -> ExecutionPlan {
            try ExecutionPlan(
                engine: .pdf, stages: [.pdf(PDFStage(source: source, encryption: encryption, pageCount: pageCount))],
                stageWeights: [1], lanes: [.cpu], outputFormat: .pdf, stagedFile: staged)
        }
    }

    @Test func itHandlesNoConversionPairYet() async {
        let engine = PDFEngine()
        #expect(engine.id == .pdf)
        #expect(ConversionCatalog.standard.pairs.allSatisfy { !engine.handles($0) })
        let pair = ConversionPair(source: .pdf, target: .png)
        #expect(await engine.availability(of: pair) == .unavailable([]))
    }

    @Test func aPlannedRewriteFillsTheStagedFileAndPassesVerify() async throws {
        let rig = try Rig()
        let plan = try rig.plan(try PDFFixtures.plain(in: rig.dir.url))

        let output = try await PDFEngine().execute(plan, context: ExecutionContext())
        try await PDFEngine().verify(output, plan: plan)

        #expect(output.url == rig.staged)
        #expect(output.format == .pdf)
        #expect(output.byteCount > 0)
        #expect(PDFDocument(url: rig.staged)?.pageCount == 2)
    }

    @Test func verifyRefusesAnOutputWithOtherPages() async throws {
        let rig = try Rig()
        let plan = try rig.plan(try PDFFixtures.plain(in: rig.dir.url), pageCount: 3)
        let output = try await PDFEngine().execute(plan, context: ExecutionContext())

        await #expect(throws: JobError.verificationFailed(PDFVerifyFailure.pageCount.message)) {
            try await PDFEngine().verify(output, plan: plan)
        }
    }

    @Test func aDamagedSourceIsRefusedAsDamagedAndLeavesTheStagedFileEmpty() async throws {
        let rig = try Rig()
        let plan = try rig.plan(try rig.dir.file("note.pdf", "These words are not a PDF."))

        await #expect(throws: JobError.unsupportedInput(.pdfDamaged)) {
            try await PDFEngine().execute(plan, context: ExecutionContext())
        }
        #expect(!FileManager.default.fileExists(atPath: rig.staged.path))
    }

    @Test func aStagedFileThatIsNotTheEmptyClaimedOneIsNeverReplaced() async throws {
        let rig = try Rig()
        try Data("someone else's".utf8).write(to: rig.staged)
        let plan = try rig.plan(try PDFFixtures.plain(in: rig.dir.url))

        await #expect(throws: JobError.internalInvariant(PDFEngine.stagedFileMessage)) {
            try await PDFEngine().execute(plan, context: ExecutionContext())
        }
        #expect(try String(contentsOf: rig.staged, encoding: .utf8) == "someone else's")
    }

    @Test func aPlanForAnotherEngineOrWithoutAPDFStageIsABug() async throws {
        let rig = try Rig()
        let image = try ExecutionPlan(
            engine: .pdf, stages: [.ffmpeg(FFmpegStage(argv: [], expectedDurationMicros: nil))], stageWeights: [1],
            lanes: [.cpu], outputFormat: .pdf, stagedFile: rig.staged)

        await #expect(throws: JobError.internalInvariant(PDFEngine.planMessage)) {
            try await PDFEngine().execute(image, context: ExecutionContext())
        }
        let output = StagedOutput(format: .pdf, url: rig.staged, byteCount: 0)
        await #expect(throws: JobError.internalInvariant(PDFEngine.planMessage)) {
            try await PDFEngine().verify(output, plan: image)
        }
    }

    @Test func prepareRefusesEveryConversion() async throws {
        let rig = try Rig()
        let source = try PDFFixtures.plain(in: rig.dir.url)
        let item = try InputItem(url: source, format: .pdf, byteCount: 4)
        let request = try JobRequest(input: item, operation: .convert(.png), destination: rig.dir.url)

        await #expect(throws: JobError.pairNotSupported(.pdf, .png)) {
            try await PDFEngine().prepare(request, workspace: JobWorkspace(job: request.id, stagedFile: rig.staged))
        }
    }

    @Test(arguments: [
        (PDFEngineError.wrongPassword, JobError.unsupportedInput(.unreadable)),
        (.damaged, .unsupportedInput(.pdfDamaged)),
        (.unsupportedEncryption, .unsupportedInput(.unreadable)),
        (.limit, .unsupportedInput(.pdfTooComplex)),
        (.io, .writeFailed(PDFEngine.writeMessage)),
        (.outputExists, .internalInvariant(PDFEngine.stagedFileMessage)),
        (.unusablePassword, .internalInvariant(PDFEngine.passwordMessage)),
        (.internalFailure, .writeFailed(PDFEngine.writeMessage)),
        (.verifyFailed(.forms), .verificationFailed(PDFVerifyFailure.forms.message)),
    ])
    func everyShimErrorBecomesAJobError(error: PDFEngineError, expected: JobError) {
        #expect(PDFEngine.jobError(error) == expected)
    }
}

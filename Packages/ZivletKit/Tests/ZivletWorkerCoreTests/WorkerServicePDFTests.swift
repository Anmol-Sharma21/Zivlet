import EnginePDF
import EngineTestSupport
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@testable import ZivletWorkerCore

/// qpdf runs only in the worker (plan 20d C5, D-M7-16): the worker's service hosts the PDF engine; a service without
/// it, like the app's in-process engines, refuses a PDF plan.
@Suite("The worker hosts the PDF engine (P2-13)")
struct WorkerServicePDFTests {
    private func pdfPlan(_ rig: WorkerRig) throws -> (JobID, ExecutionPlan) {
        let id = JobID()
        let staged = try rig.dir.folder(".zivlet-\(id)").appending(path: "staged.pdf")
        try Data().write(to: staged)
        let source = try PDFFixtures.plain(in: rig.dir.url)
        let plan = try ExecutionPlan(
            engine: .pdf, stages: [.pdf(PDFStage(source: source, encryption: .keep, pageCount: 2))],
            stageWeights: [1], lanes: [.cpu], outputFormat: .pdf, stagedFile: staged)
        return (id, plan)
    }

    @Test func aPDFPlanRunsAndVerifiesInAServiceHostingThePDFEngine() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([PDFEngine()])
        let (job, plan) = try pdfPlan(rig)

        let reply = await service.handle(.execute(job, plan, outputByteLimit: nil), events: { _ in })
        guard case .staged(let output) = reply else {
            Issue.record("not staged: \(reply)")
            return
        }
        #expect(await service.handle(.verify(output, plan), events: { _ in }) == .verified)
    }

    @Test func aServiceWithoutThePDFEngineRefusesThePlan() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine()])
        let (job, plan) = try pdfPlan(rig)

        let reply = await service.handle(.execute(job, plan, outputByteLimit: nil), events: { _ in })

        #expect(reply == .failed(.engineMissing(.pdf)))
    }
}

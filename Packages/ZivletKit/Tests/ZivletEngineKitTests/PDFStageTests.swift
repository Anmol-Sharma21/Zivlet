import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@Suite("A qpdf rewrite inside a plan (P2-13, D-M7-16)")
struct PDFStageTests {
    @Test func aPDFStageRoundTripsInsideAPlan() throws {
        let stage = PDFStage(source: URL(fileURLWithPath: "/in/a.pdf"), encryption: .remove, pageCount: 3)
        let plan = try ExecutionPlan(
            engine: .pdf, stages: [.pdf(stage)], stageWeights: [1], lanes: [.cpu], outputFormat: .pdf,
            stagedFile: URL(fileURLWithPath: "/in/.zivlet-1/staged.pdf"))

        let decoded = try JSONDecoder().decode(ExecutionPlan.self, from: JSONEncoder().encode(plan))

        #expect(decoded == plan)
        #expect(decoded.stages.first?.pdf == stage)
        #expect(decoded.stages.first?.image == nil)
        #expect(decoded.stages.first?.ffmpeg == nil)
        #expect(Stage.image(try ImagePipelineSpecTests.spec()).pdf == nil)
    }
}

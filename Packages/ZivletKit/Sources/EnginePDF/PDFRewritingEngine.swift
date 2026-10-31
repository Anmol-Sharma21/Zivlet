import ZivletCore
import ZivletEngineKit

/// An engine that writes PDFs through Quartz, with the qpdf-first rule added (D-PDF-3): its PDF output is rewritten
/// and checked as the last step of `execute`, so the engine's own `verify` and the size the app shows are about the
/// bytes that are published. The worker wraps its image engine in this. The app's in-process engines stay as they are
/// and keep Quartz's output: they have no qpdf (D-M7-16).
public struct PDFRewritingEngine: Engine {
    static let rewriteMessage = "qpdf could not rewrite the PDF."

    private let inner: any Engine
    private let watchdog: PDFWatchdog

    public init(wrapping engine: any Engine, watchdog: PDFWatchdog = .off) {
        inner = engine
        self.watchdog = watchdog
    }

    public var id: EngineID { inner.id }

    public func handles(_ pair: ConversionPair) -> Bool { inner.handles(pair) }

    public func availability(of pair: ConversionPair) async -> RouteAvailability {
        await inner.availability(of: pair)
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        try await inner.prepare(request, workspace: workspace)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        let output = try await inner.execute(plan, context: context)
        guard output.format == .pdf else { return output }
        let (url, watchdog) = (output.url, watchdog)
        let byteCount = try await BlockingWork.run { _ throws(JobError) in
            do throws(PDFEngineError) {
                return try watchdog.guarding(inputBytes: PDFEngine.size(of: url)) { () throws(PDFEngineError) in
                    try PDFRewrite.normalise(staged: url)
                }
            } catch {
                throw .verificationFailed(Self.rewriteMessage)
            }
        }
        return StagedOutput(
            format: output.format, url: output.url, byteCount: byteCount, withdrawnNotes: output.withdrawnNotes)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        try await inner.verify(output, plan: plan)
    }
}

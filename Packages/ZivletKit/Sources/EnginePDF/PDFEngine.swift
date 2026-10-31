import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// The worker's PDF engine (P2-13, plan 20d C5, D-M7-16): runs a plan's qpdf rewrite into the claimed staged file and
/// checks the result with qpdf. Only the worker hosts it; the app's in-process engines never do, so an untrusted PDF
/// never reaches qpdf inside the app. It handles no conversion pair: PDF conversions come with P2-12, and the jobs that
/// plan its rewrites (lock, unlock, change password) with plan 20f.
public struct PDFEngine: Engine {
    static let planMessage = "The PDF engine got a plan it does not run."
    static let stagedFileMessage = "The staged file is not the empty one Zivlet claimed."
    static let writeMessage = "The PDF could not be written."
    static let passwordMessage = "The password could not be passed to the PDF engine."

    public let id = EngineID.pdf
    private let limits: QPDFLimits
    private let watchdog: PDFWatchdog

    public init(limits: QPDFLimits = .standard, watchdog: PDFWatchdog = .off) {
        self.limits = limits
        self.watchdog = watchdog
    }

    public func handles(_ pair: ConversionPair) -> Bool { false }

    public func availability(of pair: ConversionPair) async -> RouteAvailability { .unavailable([]) }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        throw .pairNotSupported(request.input.format, request.target)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        let stage = try Self.stage(of: plan)
        let staged = plan.stagedFile
        let (limits, watchdog) = (limits, watchdog)
        return try await BlockingWork.run { _ throws(JobError) in
            try Self.releaseClaim(staged)
            let mode: QPDFWriterBridge.Mode = stage.encryption == .remove ? .decrypt : .preserve
            do throws(PDFEngineError) {
                try watchdog.guarding(inputBytes: Self.size(of: stage.source)) { () throws(PDFEngineError) in
                    try QPDFWriterBridge.write(stage.source, password: nil, limits: limits, mode: mode, to: staged)
                }
            } catch {
                throw Self.jobError(error)
            }
            return StagedOutput(format: .pdf, url: staged, byteCount: Self.size(of: staged))
        }
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        let stage = try Self.stage(of: plan)
        let (limits, watchdog) = (limits, watchdog)
        let expectations: [PDFExpectation] = stage.encryption == .remove ? [.unlocked] : []
        try await BlockingWork.run { _ throws(JobError) in
            do throws(PDFEngineError) {
                _ = try watchdog.guarding(inputBytes: output.byteCount) { () throws(PDFEngineError) in
                    try PDFVerify.verify(
                        output.url, pageCount: stage.pageCount, expect: expectations, limits: limits)
                }
            } catch {
                throw .verificationFailed(Self.verifyMessage(error))
            }
        }
    }

    /// The job error for a shim error; none carries a path or qpdf's own words.
    static func jobError(_ error: PDFEngineError) -> JobError {
        switch error {
        case .wrongPassword, .unsupportedEncryption: .unsupportedInput(.unreadable)
        case .damaged: .unsupportedInput(.pdfDamaged)
        case .limit: .unsupportedInput(.pdfTooComplex)
        case .io, .internalFailure: .writeFailed(writeMessage)
        case .outputExists: .internalInvariant(stagedFileMessage)
        case .unusablePassword: .internalInvariant(passwordMessage)
        case .verifyFailed(let failure): .verificationFailed(failure.message)
        }
    }

    private static func verifyMessage(_ error: PDFEngineError) -> String {
        switch error {
        case .limit: "The PDF is too complex to check."
        case .verifyFailed(let failure): failure.message
        default: PDFVerifyFailure.check.message
        }
    }

    private static func stage(of plan: ExecutionPlan) throws(JobError) -> PDFStage {
        guard plan.engine == .pdf, plan.stages.count == 1, let stage = plan.stages.first?.pdf else {
            throw .internalInvariant(planMessage)
        }
        return stage
    }

    /// The runtime claims an empty staged file in a private folder (G-16); the shim creates its output exclusively, so
    /// the empty claim is removed first, and anything else at that name is left alone.
    private static func releaseClaim(_ staged: URL) throws(JobError) {
        var info = stat()
        guard lstat(staged.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw .internalInvariant(stagedFileMessage)
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size == 0, unlink(staged.path) == 0 else {
            throw .internalInvariant(stagedFileMessage)
        }
    }

    private static func size(of url: URL) -> Int64 {
        var info = stat()
        return lstat(url.path, &info) == 0 ? Int64(info.st_size) : 0
    }
}

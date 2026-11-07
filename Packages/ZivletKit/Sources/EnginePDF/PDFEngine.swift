import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// The worker's PDF engine (P2-13, plan 20d C5, D-M7-16): plans LOCK · UNLOCK's jobs (plan 20f), runs a plan's qpdf
/// rewrite into the claimed staged file and checks the result with qpdf and PDFKit. Only the worker hosts it; the
/// app's in-process engines never do, so an untrusted PDF never reaches qpdf inside the app. It handles no conversion
/// pair (PDF conversions come with P2-12), only the protect job's `pdf → pdf`. A job's passwords reach each step
/// beside the plan, never inside it (D-M7-14).
public struct PDFEngine: Engine {
    static let planMessage = "The PDF engine got a plan it does not run."
    static let stagedFileMessage = "The staged file is not the empty one Zivlet claimed."
    static let writeMessage = "The PDF could not be written."
    static let passwordMessage = "The password could not be passed to the PDF engine."

    public let id = EngineID.pdf
    let limits: QPDFLimits
    let watchdog: PDFWatchdog

    public init(limits: QPDFLimits = .standard, watchdog: PDFWatchdog = .off) {
        self.limits = limits
        self.watchdog = watchdog
    }

    public func handles(_ pair: ConversionPair) -> Bool { pair == .protectPDF }

    public func availability(of pair: ConversionPair) async -> RouteAvailability {
        handles(pair) ? .available : .unavailable([])
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        try await prepare(request, workspace: workspace, secrets: nil)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        try await execute(plan, context: context, secrets: nil)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        try await verify(output, plan: plan, secrets: nil)
    }

    /// Pre-flight of the input with what the mode needs, then a one-stage plan (`PDFEngine+Protect`).
    public func prepare(_ request: JobRequest, workspace: JobWorkspace, secrets: JobSecrets?) async throws(JobError)
        -> ExecutionPlan
    {
        guard case .protect(let spec) = request.operation else {
            throw .pairNotSupported(request.input.format, request.target)
        }
        let engine = self
        return try await BlockingWork.run { _ throws(JobError) in
            try engine.plan(spec, source: request.input.url, workspace: workspace, secrets: secrets)
        }
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext, secrets: JobSecrets?) async throws(JobError)
        -> StagedOutput
    {
        let stage = try Self.stage(of: plan)
        let staged = plan.stagedFile
        let (limits, watchdog) = (limits, watchdog)
        // The free-disk guard (as MediaEngine's): the output is about the input's size, so one at the limit is refused
        // before qpdf writes anything.
        if let limit = context.outputByteLimit, Self.size(of: stage.source) >= limit { throw .diskFull }
        return try await BlockingWork.run { _ throws(JobError) in
            let write = try Self.write(stage, secrets)
            try Self.releaseClaim(staged)
            try Self.write(write, stage.source, to: staged, limits: limits, watchdog: watchdog)
            let withdrawn = Self.withdrawnNotes(plan.notes, staged: staged, secrets: secrets)
            return StagedOutput(format: .pdf, url: staged, byteCount: Self.size(of: staged), withdrawnNotes: withdrawn)
        }
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan, secrets: JobSecrets?) async throws(JobError) {
        let stage = try Self.stage(of: plan)
        let (limits, watchdog) = (limits, watchdog)
        let check = try Self.check(stage, secrets)
        try await BlockingWork.run { _ throws(JobError) in
            do throws(PDFEngineError) {
                _ = try watchdog.guarding(inputBytes: output.byteCount) { () throws(PDFEngineError) in
                    try PDFVerify.verify(
                        output.url, pageCount: stage.pageCount, expect: check.expectations, secrets: check.secrets,
                        limits: limits)
                }
            } catch {
                throw .verificationFailed(Self.verifyMessage(error))
            }
        }
    }

    /// One write under the watchdog, opening the input with each Unicode form of its password until one opens it (the
    /// form prepare found); a failed write leaves nothing behind, so the next form starts clean.
    private static func write(
        _ write: Write, _ source: URL, to staged: URL, limits: QPDFLimits, watchdog: PDFWatchdog
    ) throws(JobError) {
        let attempt = { (password: JobSecret?) throws(JobError) -> Bool in
            do throws(PDFEngineError) {
                try watchdog.guarding(inputBytes: size(of: source)) { () throws(PDFEngineError) in
                    try QPDFWriterBridge.write(source, password: password, limits: limits, mode: write.mode, to: staged)
                }
                return true
            } catch {
                guard error == .wrongPassword else { throw jobError(error) }
                return false
            }
        }
        guard let password = write.password else {
            guard try attempt(nil) else { throw .wrongPassword }
            return
        }
        var written = false
        try eachForm(of: password) { form throws(JobError) in
            written = try attempt(form)
            return written
        }
        guard written else { throw .wrongPassword }
    }

    /// The job error for a shim error; none carries a path or qpdf's own words.
    static func jobError(_ error: PDFEngineError) -> JobError {
        switch error {
        case .wrongPassword: .wrongPassword
        case .unsupportedEncryption: .unsupportedEncryption
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

    static func stage(of plan: ExecutionPlan) throws(JobError) -> PDFStage {
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

    static func size(of url: URL) -> Int64 {
        var info = stat()
        return lstat(url.path, &info) == 0 ? Int64(info.st_size) : 0
    }
}

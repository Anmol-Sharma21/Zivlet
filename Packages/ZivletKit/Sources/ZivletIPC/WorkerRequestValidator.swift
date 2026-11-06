import Darwin
import EngineVision
import Foundation
import ZivletCore
import ZivletEngineKit

/// The worker's boundary check (03b "parser exploit", D-M6-4): every request is validated before any engine sees it.
/// Paths must be absolute `file:` paths with no `..` component and no control character; an input must be a regular
/// file at its last component (`lstat`, so a symlink is refused); a staged file must be `staged.<ext>` inside an
/// existing `.zivlet-<job>` folder; a plan must name an engine this worker hosts; a byte limit must be positive; a PDF
/// must be within `PDFLimits`' size, measured here whatever the app said (D-M7-18). Passwords come only with a protect
/// job's steps and with text or code jobs whose inputs are all PDFs; each is 1…127 bytes, at most one per role
/// (plan 20f E3).
public struct WorkerRequestValidator: Sendable {
    public static let misplacedSecrets = JobError.internalInvariant("Passwords came with a request that takes none.")
    /// More PDFs than this in one inspection are refused, as Read QR refuses more files.
    public static let maximumInspections = 500
    public static let tooManyInspections = JobError.internalInvariant(
        "A PDF inspection takes 1 to \(maximumInspections) files.")
    /// R6 reads at most 127 bytes of a password (ISO 32000-2 §7.6.4.3.3).
    public static let passwordBytes = 1...127

    public let hostedEngines: Set<EngineID>

    public init(hostedEngines: Set<EngineID>) {
        self.hostedEngines = hostedEngines
    }

    public func validate(_ request: WorkerRequest) throws(JobError) {
        try checkSecrets(of: request)
        switch request {
        case .ping, .capabilities, .cancel: return
        case .prepare(let job, let workspace, _):
            guard workspace.job == job.id else { throw .internalInvariant("The workspace belongs to another job.") }
            try Self.checkInput(job.input.url)
            if job.input.format == .pdf { try PDFLimits.check(fileAt: job.input.url) }
            guard Self.isSafeFileURL(job.destination) else { throw .invalidDestination }
            try Self.checkStaged(workspace.stagedFile)
        case .execute(_, let plan, let limit, _):
            if let limit, limit <= 0 { throw .internalInvariant("The output byte limit must be positive.") }
            try check(plan)
        case .verify(let output, let plan, _):
            try check(plan)
            try Self.checkStaged(output.url)
        case .recognizeText(let job, _):
            try checkVision()
            try Self.check(job)
        case .textCapabilities:
            try checkVision()
        case .warmUpText(_, let languages):
            try checkVision()
            try Self.check(languages)
        case .readCodes(let job, _):
            try checkVision()
            try Self.check(job)
        case .inspectPDFs(let files):
            guard hostedEngines.contains(.pdf) else { throw .engineMissing(.pdf) }
            guard (1...Self.maximumInspections).contains(files.count) else { throw Self.tooManyInspections }
            for file in files { try Self.checkInput(file) }
        #if DEBUG
            case .selfKillForTesting, .setIdleForTesting: return
        #endif
        }
    }

    /// Where passwords may come, and their shape.
    private func checkSecrets(of request: WorkerRequest) throws(JobError) {
        guard let secrets = request.secrets else { return }
        guard Self.mayCarrySecrets(request) else { throw Self.misplacedSecrets }
        let roles = secrets.roles
        guard roles.count <= WireSecrets.Role.allCases.count, Set(roles).count == roles.count,
            secrets.byteCounts.allSatisfy(Self.passwordBytes.contains)
        else { throw .unsupportedInput(.badPassword) }
    }

    /// A protect job's steps (its plans are the PDF engine's), and text or code jobs of PDFs only.
    private static func mayCarrySecrets(_ request: WorkerRequest) -> Bool {
        switch request {
        case .prepare(let job, _, _):
            if case .protect = job.operation { return true }
            return false
        case .execute(_, let plan, _, _), .verify(_, let plan, _): return plan.engine == .pdf
        case .recognizeText(let job, _): return allPDFs(job.inputs)
        case .readCodes(let job, _): return allPDFs(job.inputs)
        default: return false
        }
    }

    private static func allPDFs(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { $0.pathExtension.lowercased() == "pdf" }
    }

    private func checkVision() throws(JobError) {
        guard hostedEngines.contains(.vision) else { throw .engineMissing(.vision) }
    }

    /// 1…200 inputs, each a regular file at a safe absolute path; 1…4 languages.
    static func check(_ job: TextJob) throws(JobError) {
        guard (1...TextJob.maximumInputs).contains(job.inputs.count) else {
            throw .internalInvariant("A text job needs 1 to \(TextJob.maximumInputs) files.")
        }
        try check(job.languages)
        for input in job.inputs { try checkInput(input) }
    }

    /// 1…500 inputs, each a regular file at a safe absolute path; a page limit of 1…500.
    static func check(_ job: CodeJob) throws(JobError) {
        guard (1...CodeJob.maximumInputs).contains(job.inputs.count) else {
            throw .internalInvariant("A code job needs 1 to \(CodeJob.maximumInputs) files.")
        }
        guard (1...PDFTextSource.pageLimit).contains(job.pageLimit) else {
            throw .internalInvariant("A code job's page limit must be 1 to \(PDFTextSource.pageLimit).")
        }
        for input in job.inputs { try checkInput(input) }
    }

    static func check(_ languages: [LanguageTag]) throws(JobError) {
        guard (1...TextJob.maximumLanguages).contains(languages.count) else {
            throw .internalInvariant("Text recognition needs 1 to \(TextJob.maximumLanguages) languages.")
        }
    }

    private func check(_ plan: ExecutionPlan) throws(JobError) {
        guard hostedEngines.contains(plan.engine) else { throw .engineMissing(plan.engine) }
        try Self.checkStaged(plan.stagedFile)
        for spec in plan.stages.compactMap(\.image) { try Self.checkInput(spec.source) }
        for stage in plan.stages.compactMap(\.pdf) {
            try Self.checkInput(stage.source)
            try PDFLimits.check(fileAt: stage.source)
        }
    }

    /// An absolute `file:` URL whose path has no `..` component and no control character (NUL included).
    static func isSafeFileURL(_ url: URL) -> Bool {
        let path = url.path
        return url.isFileURL && path.hasPrefix("/") && !path.split(separator: "/").contains("..")
            && !path.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    static func checkInput(_ url: URL) throws(JobError) {
        guard isSafeFileURL(url), fileType(url.path) == S_IFREG else { throw .unsupportedInput(.notAFile) }
    }

    /// The staged file itself may not exist yet; when it does, it must be a regular file.
    static func checkStaged(_ url: URL) throws(JobError) {
        let folder = url.deletingLastPathComponent()
        guard isSafeFileURL(url), url.lastPathComponent.hasPrefix(JobWorkspace.stagedFileStem + "."),
            folder.lastPathComponent.hasPrefix(JobWorkspace.stagingFolderPrefix), fileType(folder.path) == S_IFDIR
        else { throw .invalidDestination }
        if let type = fileType(url.path), type != S_IFREG { throw .invalidDestination }
    }

    /// The type bits of the last path component, without following a symlink; nil when nothing is there.
    static func fileType(_ path: String) -> mode_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }
}

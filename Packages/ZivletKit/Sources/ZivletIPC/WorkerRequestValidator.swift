import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// The worker's boundary check (03b "parser exploit", D-M6-4): every request is validated before any engine sees it.
/// Paths must be absolute `file:` paths with no `..` component and no control character; an input must be a regular
/// file at its last component (`lstat`, so a symlink is refused); a staged file must be `staged.<ext>` inside an
/// existing `.zivlet-<job>` folder; a plan must name an engine this worker hosts; a byte limit must be positive.
public struct WorkerRequestValidator: Sendable {
    public let hostedEngines: Set<EngineID>

    public init(hostedEngines: Set<EngineID>) {
        self.hostedEngines = hostedEngines
    }

    public func validate(_ request: WorkerRequest) throws(JobError) {
        switch request {
        case .ping, .capabilities, .cancel: return
        case .prepare(let job, let workspace):
            guard workspace.job == job.id else { throw .internalInvariant("The workspace belongs to another job.") }
            try Self.checkInput(job.input.url)
            guard Self.isSafeFileURL(job.destination) else { throw .invalidDestination }
            try Self.checkStaged(workspace.stagedFile)
        case .execute(_, let plan, let limit):
            if let limit, limit <= 0 { throw .internalInvariant("The output byte limit must be positive.") }
            try check(plan)
        case .verify(let output, let plan):
            try check(plan)
            try Self.checkStaged(output.url)
        #if DEBUG
            case .selfKillForTesting, .setIdleForTesting: return
        #endif
        }
    }

    private func check(_ plan: ExecutionPlan) throws(JobError) {
        guard hostedEngines.contains(plan.engine) else { throw .engineMissing(plan.engine) }
        try Self.checkStaged(plan.stagedFile)
        for spec in plan.stages.compactMap(\.image) { try Self.checkInput(spec.source) }
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

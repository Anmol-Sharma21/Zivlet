import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit
import os

/// Staging and atomic publication (P1-30, 03a §4.3, ADR-08). A job writes one file inside its own private hidden
/// folder, `<destination>/.zivlet-<job id>/staged.<ext>` (G-16), created exclusively so two jobs never share it and
/// on the destination's volume so publishing is one rename. Publishing copies the input's quarantine onto it, then
/// `renamex_np(RENAME_EXCL)` claims `<base>.<ext>`, `<base> 2.<ext>`, …: an existing file (the source included) is
/// never replaced, and case-insensitive volumes collide case-insensitively because the kernel decides.
public struct Publisher: Sendable {
    public static let stagingPrefix = JobWorkspace.stagingFolderPrefix
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    static let quarantineName = "com.apple.quarantine"

    let namer: OutputNamer
    let registry: FormatRegistry
    let stamp: @Sendable (URL) -> FileStamp?

    public init(namer: OutputNamer = OutputNamer(), registry: FormatRegistry = .standard) {
        self.init(namer: namer, registry: registry, stamp: FileStamp.read)
    }

    init(namer: OutputNamer, registry: FormatRegistry, stamp: @escaping @Sendable (URL) -> FileStamp?) {
        self.namer = namer
        self.registry = registry
        self.stamp = stamp
    }

    /// `<destination>/.zivlet-<job>/staged.<ext>` inside a private folder (G-16, `StagingDirectory`).
    public func claimStaging(for request: JobRequest) throws(JobError) -> JobWorkspace {
        let ext = registry.format(request.target).canonicalExtension
        let url = try StagingDirectory.claim(in: request.destination, job: request.id, ext: ext)
        return JobWorkspace(job: request.id, stagedFile: url)
    }

    /// The staged path is checked first (`StagedFile`), and the quarantine is set without following a symlink.
    public func publish(_ output: StagedOutput, for request: JobRequest) throws(JobError) -> PublishedOutput {
        try StagedFile.check(output.url)
        if let quarantine = request.input.quarantine { try copyQuarantine(quarantine, to: output.url) }
        let name = namer.conversion(source: request.input.fileName, target: request.target)
        for counter in [nil] + (2...OutputNamer.maxCandidates).map(Optional.some) {
            let destination = request.destination.appending(
                path: name.rendered(counter: counter), directoryHint: .notDirectory)
            if renamex_np(output.url.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
                removeStagingFolder(of: output.url)
                return try published(destination, format: output.format)
            }
            guard errno == EEXIST else { throw .publishFailed(errno: errno) }
        }
        throw .publishFailed(errno: EEXIST)
    }

    /// Removes a staged file and its folder after a failure or cancel. Already gone is fine; anything else is
    /// reported.
    public func discard(_ workspace: JobWorkspace) throws(JobError) {
        try StagingDirectory.remove(workspace.stagedFile)
    }

    /// The output is already published, so a folder that cannot be removed is only logged.
    private func removeStagingFolder(of stagedFile: URL) {
        do {
            try StagingDirectory.removeFolder(of: stagedFile)
        } catch {
            Self.logger.error("Staging folder not removed: \(error.logDescription, privacy: .public)")
        }
    }

    private func copyQuarantine(_ value: Data, to url: URL) throws(JobError) {
        let status = value.withUnsafeBytes { bytes in
            setxattr(url.path, Self.quarantineName, bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
        }
        guard status == 0 else { throw .publishFailed(errno: errno) }
    }

    /// The published file as it is on disk now; Undo later compares against this stamp. A file that cannot be
    /// stamped is removed again: the job fails, so nothing it reports as failed may stay behind.
    private func published(_ url: URL, format: FormatID) throws(JobError) -> PublishedOutput {
        guard let stamp = stamp(url) else {
            let code = errno
            unlink(url.path)
            throw .publishFailed(errno: code)
        }
        return PublishedOutput(
            url: url, format: format, byteCount: stamp.byteCount, fileID: stamp.fileID, modified: stamp.modified)
    }

    static func claimError(_ code: Int32, folder: URL) -> JobError {
        switch code {
        case EACCES, EPERM, EROFS: .permissionDenied(folder: folder.path)
        case ENOSPC, EDQUOT: .diskFull
        case ENOENT, ENOTDIR: .invalidDestination
        default: .publishFailed(errno: code)
        }
    }

    /// The `com.apple.quarantine` value of a file, or nil when it has none (10 §8.5: propagated, never stripped).
    public static func quarantine(of url: URL) -> Data? {
        let size = getxattr(url.path, quarantineName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = Data(count: size)
        let read = buffer.withUnsafeMutableBytes { getxattr(url.path, quarantineName, $0.baseAddress, size, 0, 0) }
        return read == size ? buffer : nil
    }
}

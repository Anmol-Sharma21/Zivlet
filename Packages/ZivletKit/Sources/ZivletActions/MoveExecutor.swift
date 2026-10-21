import Darwin
import Foundation
import ZivletRuntime

/// Runs a `MovePlan` (P1-45, 03b §7 row 4). Same volume: `renamex_np(RENAME_EXCL)`, stepping to the next free name
/// when something appeared at the target since planning. Another volume: copy into a hidden
/// `.zivlet-move-<id>` in the destination, check size and item count, rename into place exclusively, then trash
/// the original. A failed check removes the copy and leaves the original alone. Each item is independent.
nonisolated public struct MoveExecutor: Sendable {
    public typealias Copy = @Sendable (_ source: URL, _ copy: URL) throws(MoveIOError) -> Void
    public typealias Trash = @Sendable (URL) throws -> Void
    static let hiddenPrefix = ".zivlet-move-"

    private let copy: Copy
    private let trash: Trash

    public init(
        copy: @escaping Copy = MoveExecutor.copyTree,
        trash: @escaping Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.copy = copy
        self.trash = trash
    }

    @concurrent public func run(_ plan: MovePlan) async -> MoveReport {
        var moved: [MovedItem] = []
        var failures: [MoveFailure] = []
        for step in plan.steps {
            switch step.kind == .rename ? rename(step) : copyThenTrash(step, in: plan.destination) {
            case .success(let target):
                moved.append(MovedItem(source: step.source, target: target, stamp: FileStamp.read(target)))
            case .failure(let reason): failures.append(MoveFailure(url: step.source, reason: reason))
            }
        }
        return MoveReport(moved: moved, failures: failures, skipped: plan.skipped)
    }

    private func rename(_ step: MoveStep) -> Result<URL, MoveFailure.Reason> {
        claim(step) { renamex_np(step.source.path, $0.path, UInt32(RENAME_EXCL)) == 0 ? nil : errno }
            .mapError(Self.reason)
    }

    private func copyThenTrash(_ step: MoveStep, in folder: URL) -> Result<URL, MoveFailure.Reason> {
        let hidden = folder.appending(path: Self.hiddenPrefix + UUID().uuidString, directoryHint: .notDirectory)
        do {
            try copy(step.source, hidden)
        } catch {
            remove(hidden)
            return .failure(.copyFailed(errno: error.code))
        }
        guard let original = TreeSummary.read(step.source), original == TreeSummary.read(hidden) else {
            remove(hidden)
            return .failure(.verifyFailed)
        }
        let placed = claim(step) { renamex_np(hidden.path, $0.path, UInt32(RENAME_EXCL)) == 0 ? nil : errno }
        let target: URL
        switch placed {
        case .success(let claimed): target = claimed
        case .failure(let error):
            remove(hidden)
            return .failure(Self.reason(error))
        }
        do {
            try trash(step.source)
        } catch {
            return .failure(.originalKept)
        }
        return .success(target)
    }

    /// Tries the planned target, then `name 2`, `name 3`, … while the kernel answers `EEXIST`.
    private func claim(_ step: MoveStep, _ attempt: (URL) -> Int32?) -> Result<URL, MoveIOError> {
        let folder = step.target.deletingLastPathComponent()
        let name = step.source.lastPathComponent
        for counter in [nil] + (2...MoveNames.maxCandidates).map(Optional.some) {
            let target =
                counter.map {
                    folder.appending(
                        path: MoveNames.candidate(name, counter: $0, kind: step.itemKind), directoryHint: .notDirectory)
                } ?? step.target
            guard let code = attempt(target) else { return .success(target) }
            guard code == EEXIST else { return .failure(MoveIOError(code: code)) }
        }
        return .failure(MoveIOError(code: EEXIST))
    }

    private static func reason(_ error: MoveIOError) -> MoveFailure.Reason {
        error.code == EEXIST ? .noFreeName : .moveFailed(errno: error.code)
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// `copyfile` with metadata, recursion, no overwrite and symlinks copied as links.
    public static let copyTree: Copy = { source, copy throws(MoveIOError) in
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW)
        guard copyfile(source.path, copy.path, nil, flags) == 0 else { throw MoveIOError(code: errno) }
    }
}

/// Item count and total bytes of regular files under a path (the path itself included), without following
/// symlinks. AppleDouble `._` files that some volumes add for metadata are not counted.
nonisolated struct TreeSummary: Equatable {
    let items: Int
    let bytes: Int64

    static func read(_ url: URL) -> TreeSummary? {
        guard let root = entry(url) else { return nil }
        var summary = root
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return root }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return root
        }
        for case let child as URL in walker where !child.lastPathComponent.hasPrefix("._") {
            guard let next = entry(child) else { return nil }
            summary = TreeSummary(items: summary.items + next.items, bytes: summary.bytes + next.bytes)
        }
        return summary
    }

    private static func entry(_ url: URL) -> TreeSummary? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let isFile = (info.st_mode & S_IFMT) == S_IFREG
        return TreeSummary(items: 1, bytes: isFile ? Int64(info.st_size) : 0)
    }
}

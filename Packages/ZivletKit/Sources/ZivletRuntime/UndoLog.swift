import Darwin
import Foundation
import ZivletCore

/// What identifies a file Zivlet wrote: inode, size and modification time (03a §4.7).
public struct FileStamp: Sendable, Equatable {
    public let fileID: UInt64
    public let byteCount: Int64
    public let modified: Date

    public init(fileID: UInt64, byteCount: Int64, modified: Date) {
        self.fileID = fileID
        self.byteCount = byteCount
        self.modified = modified
    }

    /// The stamp of the file at `url` now, or nil when nothing is there.
    public static func read(_ url: URL) -> FileStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let time = info.st_mtimespec
        return FileStamp(
            fileID: UInt64(info.st_ino), byteCount: Int64(info.st_size),
            modified: Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9))
    }
}

/// One output of an undoable batch, as it was published.
public struct UndoOutput: Sendable, Equatable, Codable {
    public let url: URL
    public let fileID: UInt64
    public let byteCount: Int64
    public let modified: Date

    public init(_ output: PublishedOutput) {
        url = output.url
        fileID = output.fileID
        byteCount = output.byteCount
        modified = output.modified
    }

    var stamp: FileStamp { FileStamp(fileID: fileID, byteCount: byteCount, modified: modified) }
}

/// One undoable batch (03a §4.7). Move entries arrive with the Move action.
public struct UndoEntry: Sendable, Equatable, Codable {
    public let batch: BatchID
    public let date: Date
    public let outputs: [UndoOutput]

    public init(batch: BatchID, date: Date, outputs: [UndoOutput]) {
        self.batch = batch
        self.date = date
        self.outputs = outputs
    }
}

/// The undo history, newest first: the last 20 batches, each kept for 24 hours (03a §4.7). Immutable; every change
/// returns a new log.
public struct UndoLog: Sendable, Equatable, Codable {
    public static let capacity = 20
    public static let lifetime: TimeInterval = 24 * 60 * 60

    public let entries: [UndoEntry]

    public init(entries: [UndoEntry] = []) { self.entries = entries }

    /// Adds `entry` as the newest; an entry without outputs has nothing to undo and is not kept.
    public func recording(_ entry: UndoEntry, now: Date) -> UndoLog {
        guard !entry.outputs.isEmpty else { return pruned(now: now) }
        let others = entries.filter { $0.batch != entry.batch }
        return UndoLog(entries: Array(([entry] + others).prefix(Self.capacity))).pruned(now: now)
    }

    public func removing(_ batch: BatchID) -> UndoLog {
        UndoLog(entries: entries.filter { $0.batch != batch })
    }

    /// The batch's entry with only the outputs at `urls`, in place; removed when none are left.
    public func keeping(_ batch: BatchID, outputs urls: Set<URL>) -> UndoLog {
        UndoLog(
            entries: entries.compactMap { entry in
                guard entry.batch == batch else { return entry }
                let kept = entry.outputs.filter { urls.contains($0.url) }
                return kept.isEmpty ? nil : UndoEntry(batch: entry.batch, date: entry.date, outputs: kept)
            })
    }

    /// Drops entries older than `lifetime`.
    public func pruned(now: Date) -> UndoLog {
        UndoLog(entries: entries.filter { now.timeIntervalSince($0.date) <= Self.lifetime })
    }

    public func entry(for batch: BatchID) -> UndoEntry? { entries.first { $0.batch == batch } }
}

/// Why an output was left in place.
public enum UndoSkipReason: String, Sendable, Equatable, Codable {
    /// Edited, replaced or touched since Zivlet saved it.
    case changed
    /// No longer at its path.
    case missing
    /// The Trash refused it (permissions, volume without a Trash).
    case trashFailed
}

public struct UndoSkip: Sendable, Equatable {
    public let url: URL
    public let reason: UndoSkipReason

    public init(url: URL, reason: UndoSkipReason) {
        self.url = url
        self.reason = reason
    }
}

/// What an undo will do: outputs still exactly as published go to the Trash; every other one is listed.
public struct UndoPlan: Sendable, Equatable {
    public let trash: [URL]
    public let skipped: [UndoSkip]
}

public enum UndoPlanner {
    /// Pure: `stamp` reads the file as it is now (nil = missing).
    public static func plan(_ entry: UndoEntry, stamp: (URL) -> FileStamp?) -> UndoPlan {
        var trash: [URL] = []
        var skipped: [UndoSkip] = []
        for output in entry.outputs {
            switch stamp(output.url) {
            case .none: skipped.append(UndoSkip(url: output.url, reason: .missing))
            case .some(let current) where current == output.stamp: trash.append(output.url)
            case .some: skipped.append(UndoSkip(url: output.url, reason: .changed))
            }
        }
        return UndoPlan(trash: trash, skipped: skipped)
    }
}

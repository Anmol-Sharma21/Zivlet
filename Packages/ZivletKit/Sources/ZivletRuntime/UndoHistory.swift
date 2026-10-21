import Foundation
import ZivletCore
import os

public enum UndoStoreError: Error, Sendable, Equatable {
    case writeFailed(String)
}

/// The undo log on disk: `~/Library/Application Support/Zivlet/undo.json` (03a §4.7). A missing file is an empty
/// log; an unreadable one is logged and treated as empty, so a damaged file never blocks conversions.
public struct UndoStore: Sendable {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "undo")

    public let file: URL

    public init(file: URL) { self.file = file }

    public static func standard() -> UndoStore {
        UndoStore(
            file: URL.applicationSupportDirectory.appending(path: "Zivlet/undo.json", directoryHint: .notDirectory))
    }

    public func load() -> UndoLog {
        guard let data = try? Data(contentsOf: file) else { return UndoLog() }
        do {
            return try JSONDecoder().decode(UndoLog.self, from: data)
        } catch {
            Self.logger.error(
                "Undo history unreadable, starting empty: \(String(describing: error), privacy: .private)")
            return UndoLog()
        }
    }

    public func save(_ log: UndoLog) throws(UndoStoreError) {
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(log).write(to: file, options: .atomic)
        } catch {
            throw .writeFailed(String(describing: error))
        }
    }
}

/// The outcome of one undo, and the sentence the result card shows for it.
public struct UndoResult: Sendable, Equatable {
    public let trashed: [URL]
    public let skipped: [UndoSkip]

    public init(trashed: [URL], skipped: [UndoSkip]) {
        self.trashed = trashed
        self.skipped = skipped
    }

    /// Some files were refused by the Trash and stay in the history, so Undo can be pressed again.
    public var canRetry: Bool { skipped.contains { $0.reason == .trashFailed } }

    /// One sentence per outcome, trashed first; "Moved to the Trash." alone when nothing was left in place.
    public var message: String {
        guard !skipped.isEmpty else { return "Moved to the Trash." }
        let moved = trashed.isEmpty ? [] : [Self.files(trashed.count) + " moved to the Trash."]
        let reasons: [UndoSkipReason] = [.changed, .missing, .trashFailed]
        let left = reasons.compactMap { reason -> String? in
            let count = skipped.filter { $0.reason == reason }.count
            return count == 0 ? nil : Self.sentence(reason, count: count)
        }
        return (moved + left).joined(separator: " ")
    }

    private static func files(_ count: Int) -> String { count == 1 ? "1 file" : "\(count) files" }

    private static func sentence(_ reason: UndoSkipReason, count: Int) -> String {
        let one = count == 1
        switch reason {
        case .changed:
            return files(count) + " changed since " + (one ? "it was" : "they were") + " saved, so "
                + (one ? "it was" : "they were") + " left in place."
        case .missing: return files(count) + (one ? " was" : " were") + " no longer there."
        case .trashFailed: return files(count) + " couldn't be moved to the Trash; Undo can try again."
        }
    }
}

/// Records finished batches and undoes them (P1-15): the log is loaded once, and every change is written back.
public actor UndoHistory {
    public typealias Trash = @Sendable (URL) throws -> Void

    private let store: UndoStore
    private let now: @Sendable () -> Date
    private let trash: Trash
    private var log: UndoLog

    public init(
        store: UndoStore = .standard(), now: @escaping @Sendable () -> Date = { Date() },
        trash: @escaping Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.store = store
        self.now = now
        self.trash = trash
        log = store.load().pruned(now: now())
    }

    public func record(_ batch: BatchID, outputs: [PublishedOutput]) {
        let date = now()
        update(log.recording(UndoEntry(batch: batch, date: date, outputs: outputs.map(UndoOutput.init)), now: date))
    }

    /// Nil when the batch is not (or no longer) undoable. Outputs the Trash refused stay in the entry so Undo can be
    /// retried; trashed, changed and missing ones leave it, and an entry with nothing left is removed.
    public func undo(_ batch: BatchID) -> UndoResult? {
        guard let entry = log.pruned(now: now()).entry(for: batch) else { return nil }
        let plan = UndoPlanner.plan(entry, stamp: FileStamp.read)
        var trashed: [URL] = []
        var skipped = plan.skipped
        for url in plan.trash {
            do {
                try trash(url)
                trashed.append(url)
            } catch {
                UndoStore.logger.error("Undo: Trash refused a file: \(String(describing: error), privacy: .private)")
                skipped.append(UndoSkip(url: url, reason: .trashFailed))
            }
        }
        let retry = Set(skipped.filter { $0.reason == .trashFailed }.map(\.url))
        update(log.keeping(batch, outputs: retry))
        return UndoResult(trashed: trashed, skipped: skipped)
    }

    /// Keeps the new log in memory even when it cannot be written; the failure is logged.
    private func update(_ next: UndoLog) {
        log = next
        do {
            try store.save(next)
        } catch {
            UndoStore.logger.error("Undo history not saved: \(String(describing: error), privacy: .private)")
        }
    }
}

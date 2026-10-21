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

/// Records finished batches and Moves and undoes them (P1-15): the log is loaded once, and every change is written
/// back.
public actor UndoHistory {
    public typealias Trash = @Sendable (URL) throws -> Void
    /// Moves an item from its current place (first) back to its old one (second); never replaces anything.
    public typealias MoveBack = @Sendable (URL, URL) throws -> Void

    private let store: UndoStore
    private let now: @Sendable () -> Date
    private let trash: Trash
    private let moveBack: MoveBack
    private var log: UndoLog

    public init(
        store: UndoStore = .standard(), now: @escaping @Sendable () -> Date = { Date() },
        trash: @escaping Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        moveBack: @escaping MoveBack = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) {
        self.store = store
        self.now = now
        self.trash = trash
        self.moveBack = moveBack
        log = store.load().pruned(now: now())
    }

    public func record(_ batch: BatchID, outputs: [PublishedOutput]) {
        let date = now()
        update(log.recording(UndoEntry(batch: batch, date: date, outputs: outputs.map(UndoOutput.init)), now: date))
    }

    public func record(_ batch: BatchID, moves: [UndoMove]) {
        let date = now()
        update(log.recording(UndoEntry(batch: batch, date: date, moves: moves), now: date))
    }

    /// The entries that can still be undone, newest first (the status menu's Recent Results).
    public func recent() -> [UndoEntry] { log.pruned(now: now()).entries }

    /// Nil when the batch is not (or no longer) undoable. Outputs the Trash refused (or items that could not be moved
    /// back) stay in the entry so Undo can be retried; the rest leave it, and an entry with nothing left is removed.
    public func undo(_ batch: BatchID) -> UndoResult? {
        guard let entry = log.pruned(now: now()).entry(for: batch) else { return nil }
        return entry.kind == .move ? undoMoves(entry) : undoOutputs(entry)
    }

    private func undoOutputs(_ entry: UndoEntry) -> UndoResult {
        let batch = entry.batch
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

    private func undoMoves(_ entry: UndoEntry) -> UndoResult {
        let plan = MoveUndoPlanner.plan(entry.moves, stamp: FileStamp.read, occupied: MoveUndoPlanner.isOccupied)
        var restored: [URL] = []
        var skipped = plan.skipped
        for move in plan.restore {
            do {
                try moveBack(move.moved, move.original)
                restored.append(move.original)
            } catch {
                UndoStore.logger.error(
                    "Undo: an item couldn't be moved back: \(String(describing: error), privacy: .private)")
                skipped.append(UndoSkip(url: move.moved, reason: .moveFailed))
            }
        }
        let retry = Set(skipped.filter { $0.reason == .moveFailed }.map(\.url))
        update(log.keeping(entry.batch, outputs: retry))
        return UndoResult(kind: .move, restored: restored, skipped: skipped)
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

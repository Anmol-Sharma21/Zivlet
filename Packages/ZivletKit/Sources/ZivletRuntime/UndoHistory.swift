import Foundation
import ZivletCore
import os

public enum UndoStoreError: Error, Sendable, Equatable {
    case writeFailed(String)
}

/// The undo log on disk: `~/Library/Application Support/Zivlet/undo.json` (03a §4.7). A missing file is an empty
/// log; an undecodable one is logged, set aside as `undo.damaged.json` and treated as empty, so a damaged file never
/// blocks conversions and is never silently replaced. A file a later Zivlet wrote (a newer schema) is read as empty
/// and never overwritten.
public struct UndoStore: Sendable {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")
    static let damagedName = "undo.damaged.json"

    public let file: URL
    private let newer = NewerFlag()

    public init(file: URL) { self.file = file }

    public static func standard() -> UndoStore {
        UndoStore(
            file: URL.applicationSupportDirectory.appending(path: "Zivlet/undo.json", directoryHint: .notDirectory))
    }

    public func load() -> UndoLog {
        guard let data = try? Data(contentsOf: file) else { return UndoLog() }
        if let header = try? JSONDecoder().decode(UndoHeader.self, from: data), (header.schema ?? 1) > UndoLog.schema {
            Self.logger.error("Undo history has newer schema \(header.schema ?? 0, privacy: .public); left untouched")
            newer.set()
            return UndoLog()
        }
        do {
            return try JSONDecoder().decode(UndoLog.self, from: data)
        } catch {
            Self.logger.error(
                "Undo history unreadable, starting empty: \(String(describing: error), privacy: .private)")
            setAside()
            return UndoLog()
        }
    }

    /// Renames the file to the first free "undo.damaged.json", "undo.damaged 2.json" …; an earlier one stays.
    private func setAside() {
        let folder = file.deletingLastPathComponent()
        let names = [Self.damagedName] + (2...99).map { "undo.damaged \($0).json" }
        guard
            let free = names.map({ folder.appending(path: $0) }).first(where: {
                !FileManager.default.fileExists(atPath: $0.path)
            }), (try? FileManager.default.moveItem(at: file, to: free)) != nil
        else { return Self.logger.error("Undo history could not be set aside") }
    }

    public func save(_ log: UndoLog) throws(UndoStoreError) {
        guard !newer.isSet else { throw .writeFailed("a newer Zivlet wrote the undo history") }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(log).write(to: file, options: .atomic)
        } catch {
            throw .writeFailed(String(describing: error))
        }
    }
}

/// Only the schema of `undo.json`, read first so a newer file is recognised before its entries.
private struct UndoHeader: Decodable {
    let schema: Int?
}

/// Whether the store read a newer file, shared by the store's copies.
private final class NewerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
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

    public func record(_ batch: BatchID, copies: [UndoCopy]) {
        let date = now()
        update(log.recording(UndoEntry(batch: batch, date: date, copies: copies), now: date))
    }

    /// The entries that can still be undone, newest first (the status menu's Recent Results).
    public func recent() -> [UndoEntry] { log.pruned(now: now()).entries }

    /// Nil when the batch is not (or no longer) undoable. Outputs the Trash refused (or items that could not be moved
    /// back) stay in the entry so Undo can be retried; the rest leave it, and an entry with nothing left is removed.
    public func undo(_ batch: BatchID) -> UndoResult? {
        guard let entry = log.pruned(now: now()).entry(for: batch) else { return nil }
        switch entry.kind {
        case .move: return undoMoves(entry)
        case .copy: return undoTrashing(entry, plan: UndoPlanner.plan(copies: entry.copies, stamp: FileStamp.read))
        case .conversion: return undoTrashing(entry, plan: UndoPlanner.plan(entry, stamp: FileStamp.read))
        }
    }

    /// Conversion outputs and copies: what is unchanged goes to the Trash.
    private func undoTrashing(_ entry: UndoEntry, plan: UndoPlan) -> UndoResult {
        let batch = entry.batch
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
        return UndoResult(kind: entry.kind, trashed: trashed, skipped: skipped)
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

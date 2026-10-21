import Foundation
import Testing
import ZivletCore

@testable import ZivletRuntime

@Suite("Undo for moves: put items back when unchanged and the old place is free (P1-15, P1-45, G-7)")
struct UndoMoveTests {
    static let start = UndoLogTests.start

    static func move(_ original: String, _ moved: String, id: UInt64 = 1, bytes: Int64 = 3) -> UndoMove {
        UndoMove(
            original: URL(fileURLWithPath: original), moved: URL(fileURLWithPath: moved),
            stamp: FileStamp(fileID: id, byteCount: bytes, modified: start))
    }

    @Test func anOldHistoryWithoutMovesStillLoads() throws {
        let batch = BatchID()
        let json = """
            {"entries":[{"batch":{"raw":"\(batch.raw.uuidString)"},"date":0,"outputs":[]}]}
            """
        let log = try JSONDecoder().decode(UndoLog.self, from: Data(json.utf8))
        #expect(log.entries.map(\.batch) == [batch] && log.entries.first?.moves == [])
        #expect(log.entries.first?.kind == .conversion)
    }

    @Test func aMoveEntryIsKeptAndRoundTrips() throws {
        let entry = UndoEntry(batch: BatchID(), date: Self.start, moves: [Self.move("/a/x.txt", "/b/x.txt")])
        let log = UndoLog().recording(entry, now: Self.start)
        #expect(log.entries == [entry] && entry.kind == .move)
        #expect(try JSONDecoder().decode(UndoLog.self, from: JSONEncoder().encode(log)) == log)
        #expect(UndoLog().recording(UndoEntry(batch: BatchID(), date: Self.start), now: Self.start).entries.isEmpty)
    }

    @Test func thePlanRestoresUnchangedItemsWhoseOldPlaceIsFree() {
        let moves = [
            Self.move("/a/same", "/b/same"), Self.move("/a/edited", "/b/edited"), Self.move("/a/gone", "/b/gone"),
            Self.move("/a/taken", "/b/taken"),
        ]
        let now: [String: FileStamp] = [
            "/b/same": FileStamp(fileID: 1, byteCount: 3, modified: Self.start),
            "/b/edited": FileStamp(fileID: 1, byteCount: 8, modified: Self.start),
            "/b/taken": FileStamp(fileID: 1, byteCount: 3, modified: Self.start),
        ]
        let plan = MoveUndoPlanner.plan(moves, stamp: { now[$0.path] }, occupied: { $0.path == "/a/taken" })
        #expect(plan.restore.map(\.moved.path) == ["/b/same"])
        #expect(
            plan.skipped == [
                UndoSkip(url: URL(fileURLWithPath: "/b/edited"), reason: .changed),
                UndoSkip(url: URL(fileURLWithPath: "/b/gone"), reason: .missing),
                UndoSkip(url: URL(fileURLWithPath: "/b/taken"), reason: .originalTaken),
            ])
    }

    @Test func undoPutsAMovedFileBackWithItsInode() async throws {
        let box = try Sandbox()
        let original = try box.file("a.txt", "abc")
        let moved = box.dir.appending(path: "moved.txt")
        try FileManager.default.moveItem(at: original, to: moved)
        let stamp = try #require(FileStamp.read(moved))
        let history = Self.history(box)
        let batch = BatchID()
        await history.record(batch, moves: [UndoMove(original: original, moved: moved, stamp: stamp)])
        let result = try #require(await history.undo(batch))
        #expect(result.restored == [original] && result.skipped.isEmpty && result.message == "Moved back.")
        #expect(FileStamp.read(original)?.fileID == stamp.fileID && FileStamp.read(moved) == nil)
        #expect(await history.undo(batch) == nil)
    }

    @Test func aMoveBackThatFailsCanBeTriedAgain() async throws {
        let box = try Sandbox()
        let moved = try box.file("moved.txt", "abc")
        let original = box.dir.appending(path: "folder/a.txt")
        let stamp = try #require(FileStamp.read(moved))
        let history = Self.history(box)
        let batch = BatchID()
        await history.record(batch, moves: [UndoMove(original: original, moved: moved, stamp: stamp)])
        let first = try #require(await history.undo(batch))
        #expect(first.skipped == [UndoSkip(url: moved, reason: .moveFailed)] && first.canRetry)
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        let second = try #require(await history.undo(batch))
        #expect(second.restored == [original] && !second.canRetry)
    }

    @Test func moveUndoCopySaysWhatHappened() {
        let url = URL(fileURLWithPath: "/x/a")
        func skip(_ reason: UndoSkipReason) -> UndoSkip { UndoSkip(url: url, reason: reason) }
        func moves(_ restored: Int, _ skipped: [UndoSkip]) -> String {
            UndoResult(kind: .move, restored: Array(repeating: url, count: restored), skipped: skipped).message
        }
        #expect(moves(2, []) == "Moved back.")
        #expect(moves(0, [skip(.changed)]) == "1 item changed since it was moved, so it was left in place.")
        #expect(moves(1, [skip(.missing), skip(.missing)]) == "1 item moved back. 2 items were no longer there.")
        #expect(
            moves(0, [skip(.originalTaken), skip(.moveFailed)])
                == "1 item stayed put because something else is in its old place. "
                + "1 item couldn't be moved back; Undo can try again.")
        #expect(moves(0, [skip(.changed), skip(.changed)]).hasPrefix("2 items changed since they were moved"))
    }

    static func history(_ box: Sandbox) -> UndoHistory {
        UndoHistory(
            store: UndoStore(file: box.dir.appending(path: "undo.json")), now: { start },
            trash: { _ in Issue.record("a move undo never trashes") })
    }
}

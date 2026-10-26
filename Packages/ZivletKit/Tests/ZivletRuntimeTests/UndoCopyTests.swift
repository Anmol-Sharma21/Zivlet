import Foundation
import Testing
import ZivletCore

@testable import ZivletRuntime

@Suite("Undo for Copy to…: trash unchanged copies, keep changed ones (P2-142, D-M5b-13)")
struct UndoCopyTests {
    static let start = UndoLogTests.start

    static func copy(_ path: String, id: UInt64 = 1, bytes: Int64 = 3) -> UndoCopy {
        UndoCopy(copy: URL(fileURLWithPath: path), stamp: FileStamp(fileID: id, byteCount: bytes, modified: start))
    }

    @Test func aSchemaOneHistoryDecodesWithNoCopies() throws {
        let batch = BatchID()
        let json = """
            {"entries":[{"batch":{"raw":"\(batch.raw.uuidString)"},"date":0,"outputs":[],"moves":[]}]}
            """
        let log = try JSONDecoder().decode(UndoLog.self, from: Data(json.utf8))
        #expect(log.entries.first?.copies == [] && log.entries.first?.kind == .conversion)
    }

    @Test func aCopyEntryRoundTripsAsSchemaTwo() throws {
        let entry = UndoEntry(batch: BatchID(), date: Self.start, copies: [Self.copy("/b/a 2.txt")])
        let log = UndoLog().recording(entry, now: Self.start)
        let data = try JSONEncoder().encode(log)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["schema"] as? Int == 2)
        #expect(try JSONDecoder().decode(UndoLog.self, from: data) == log && entry.kind == .copy)
    }

    @Test func keepingFiltersCopiesByTheirURL() {
        let batch = BatchID()
        let entry = UndoEntry(batch: batch, date: Self.start, copies: [Self.copy("/b/x"), Self.copy("/b/y")])
        let log = UndoLog(entries: [entry])
        #expect(
            log.keeping(batch, outputs: [URL(fileURLWithPath: "/b/y")]).entries.first?.copies.map(\.copy.path) == [
                "/b/y"
            ])
        #expect(log.keeping(batch, outputs: []).entries.isEmpty)
    }

    @Test func undoTrashesUnchangedCopiesAndKeepsAChangedOne() async throws {
        let box = try Sandbox()
        let same = try box.file("a 2.txt", "abc")
        let edited = try box.file("photo 2.heic", "abc")
        let copies = try [same, edited].map { UndoCopy(copy: $0, stamp: try #require(FileStamp.read($0))) }
        try Data("changed since".utf8).write(to: edited)
        let trashed = Trashed()
        let history = UndoHistory(
            store: UndoStore(file: box.dir.appending(path: "undo.json")), now: { Self.start },
            trash: { trashed.add($0) })
        let batch = BatchID()
        await history.record(batch, copies: copies)
        let result = try #require(await history.undo(batch))
        #expect(trashed.urls == [same] && result.kind == .copy && result.trashed == [same])
        #expect(result.skipped == [UndoSkip(url: edited, reason: .changed)])
        #expect(
            result.message == "1 item moved to the Trash. photo 2.heic changed since it was copied, so it was kept.")
        #expect(await history.undo(batch) == nil)
    }

    @Test func copyUndoSaysWhatHappened() {
        let url = URL(fileURLWithPath: "/x/a.txt")
        func copies(_ trashed: Int, _ skipped: [UndoSkip]) -> String {
            UndoResult(kind: .copy, trashed: Array(repeating: url, count: trashed), skipped: skipped).message
        }
        #expect(copies(2, []) == "Moved to the Trash.")
        #expect(copies(0, [UndoSkip(url: url, reason: .missing)]) == "1 item was no longer there.")
        #expect(
            copies(0, [UndoSkip(url: url, reason: .trashFailed)])
                == "1 item couldn't be moved to the Trash; Undo can try again.")
    }
}

/// The URLs a test's Trash received, in order.
final class Trashed: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [URL] = []

    var urls: [URL] { lock.withLock { received } }

    func add(_ url: URL) { lock.withLock { received.append(url) } }
}

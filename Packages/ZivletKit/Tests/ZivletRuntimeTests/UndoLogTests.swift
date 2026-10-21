import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

@Suite("Undo log: entries, revert plans, persistence and history (P1-15, 03a §4.7)")
struct UndoLogTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func output(_ path: String, id: UInt64 = 1, bytes: Int64 = 3, modified: Date = start) -> PublishedOutput {
        PublishedOutput(url: URL(fileURLWithPath: path), format: .png, byteCount: bytes, fileID: id, modified: modified)
    }

    static func entry(_ batch: BatchID = BatchID(), at date: Date = start, _ outputs: [PublishedOutput] = [])
        -> UndoEntry
    {
        UndoEntry(batch: batch, date: date, outputs: outputs.map(UndoOutput.init))
    }

    @Test func recentListsTheUndoableEntriesNewestFirst() async throws {
        let box = try Sandbox()
        let history = UndoHistory(store: UndoStore(file: box.dir.appending(path: "undo.json")), now: { Self.start })
        let (a, b) = (BatchID(), BatchID())
        await history.record(a, outputs: [Self.output("/x/a.png")])
        await history.record(b, outputs: [Self.output("/x/b.png")])
        #expect(await history.recent().map(\.batch) == [b, a])
    }

    @Test func publishStampsTheOutputWithItsInodeSizeAndModificationTime() throws {
        let box = try Sandbox()
        let request = try box.request("a.png", .png, to: .jpg)
        let workspace = try Publisher().claimStaging(for: request)
        try Data("abcd".utf8).write(to: workspace.stagedFile)
        let staged = StagedOutput(format: .jpg, url: workspace.stagedFile, byteCount: 4)
        let published = try Publisher().publish(staged, for: request)
        let stamp = FileStamp.read(published.url)
        #expect(stamp == FileStamp(fileID: published.fileID, byteCount: 4, modified: published.modified))
    }

    @Test func recordingKeepsTheNewestTwentyAndForgetsEntriesOlderThanADay() {
        let file = [Self.output("/x/a.png")]
        let old = Self.entry(at: Self.start, file)
        var log = UndoLog().recording(old, now: Self.start)
        let later = Self.start.addingTimeInterval(UndoLog.lifetime + 1)
        let recent = (0..<25).map { Self.entry(at: later.addingTimeInterval(Double($0)), file) }
        for entry in recent { log = log.recording(entry, now: entry.date) }
        #expect(log.entries.count == UndoLog.capacity)
        #expect(log.entries.first == recent.last && !log.entries.contains(old))
        #expect(log.pruned(now: later.addingTimeInterval(2 * UndoLog.lifetime)).entries.isEmpty)
    }

    @Test func anEntryWithoutOutputsIsNotRecordedAndRemovingForgetsABatch() {
        let empty = Self.entry()
        let kept = Self.entry(BatchID(), [Self.output("/x/a.png")])
        let log = UndoLog().recording(empty, now: Self.start).recording(kept, now: Self.start)
        #expect(log.entries == [kept] && log.entry(for: kept.batch) == kept)
        #expect(log.removing(kept.batch).entries.isEmpty && log.entry(for: empty.batch) == nil)
    }

    @Test func thePlanTrashesUnchangedOutputsAndListsEveryOtherOne() {
        let outputs = [
            Self.output("/x/same.png"), Self.output("/x/edited.png"), Self.output("/x/touched.png"),
            Self.output("/x/replaced.png"), Self.output("/x/gone.png"),
        ]
        let disk: [String: FileStamp] = [
            "/x/same.png": FileStamp(fileID: 1, byteCount: 3, modified: Self.start),
            "/x/edited.png": FileStamp(fileID: 1, byteCount: 9, modified: Self.start),
            "/x/touched.png": FileStamp(fileID: 1, byteCount: 3, modified: Self.start.addingTimeInterval(5)),
            "/x/replaced.png": FileStamp(fileID: 2, byteCount: 3, modified: Self.start),
        ]
        let plan = UndoPlanner.plan(Self.entry(BatchID(), outputs)) { disk[$0.path] }
        #expect(plan.trash.map(\.lastPathComponent) == ["same.png"])
        #expect(
            plan.skipped == [
                UndoSkip(url: URL(fileURLWithPath: "/x/edited.png"), reason: .changed),
                UndoSkip(url: URL(fileURLWithPath: "/x/touched.png"), reason: .changed),
                UndoSkip(url: URL(fileURLWithPath: "/x/replaced.png"), reason: .changed),
                UndoSkip(url: URL(fileURLWithPath: "/x/gone.png"), reason: .missing),
            ])
    }

    @Test func theStoreRoundTripsAndAMissingOrCorruptFileLoadsEmpty() throws {
        let box = try Sandbox()
        let store = UndoStore(file: box.dir.appending(path: "Zivlet/undo.json"))
        #expect(store.load() == UndoLog())
        let log = UndoLog().recording(Self.entry(BatchID(), [Self.output("/x/a.png")]), now: Self.start)
        try store.save(log)
        #expect(store.load() == log)
        try Data("not json".utf8).write(to: store.file)
        #expect(store.load() == UndoLog())
    }

    @Test func aStoreThatCannotBeWrittenIsATypedError() throws {
        let box = try Sandbox()
        let blocker = try box.file("blocker")
        let store = UndoStore(file: blocker.appending(path: "undo.json"))
        #expect(throws: UndoStoreError.self) { try store.save(UndoLog()) }
    }
}

@Suite("Undo history: record a batch, undo it once, keep it across launches (P1-15)")
struct UndoHistoryTests {
    final class Mover: @unchecked Sendable {
        private(set) var moved: [URL] = []
        var failing: Set<String> = []
        func move(_ url: URL) throws {
            if failing.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
            moved.append(url)
        }
    }

    @Test func aRecordedBatchIsUndoneOnceAndSurvivesARelaunch() async throws {
        let box = try Sandbox()
        let file = box.dir.appending(path: "undo.json")
        let output = try Self.published(box, "a.png")
        let mover = Mover()
        let batch = BatchID()
        let first = UndoHistory(store: UndoStore(file: file), now: { UndoLogTests.start }, trash: mover.move)
        await first.record(batch, outputs: [output])
        let relaunched = UndoHistory(store: UndoStore(file: file), now: { UndoLogTests.start }, trash: mover.move)
        let result = try #require(await relaunched.undo(batch))
        #expect(result.trashed == [output.url] && result.skipped.isEmpty && mover.moved == [output.url])
        #expect(await relaunched.undo(batch) == nil)
        #expect(UndoStore(file: file).load().entries.isEmpty)
    }

    @Test func aFileTheTrashRefusesIsListedNotIgnored() async throws {
        let box = try Sandbox()
        let output = try Self.published(box, "locked.png")
        let mover = Mover()
        mover.failing = ["locked.png"]
        let history = UndoHistory(
            store: UndoStore(file: box.dir.appending(path: "undo.json")), now: { UndoLogTests.start },
            trash: mover.move)
        let batch = BatchID()
        await history.record(batch, outputs: [output])
        let result = try #require(await history.undo(batch))
        #expect(result.trashed.isEmpty && result.skipped == [UndoSkip(url: output.url, reason: .trashFailed)])
    }

    /// Only files the Trash refused stay undoable (they may just have been busy); trashed, changed and missing ones
    /// leave the entry, which goes once nothing is left to retry.
    @Test func filesTheTrashRefusedCanBeUndoneAgain() async throws {
        let box = try Sandbox()
        let locked = try Self.published(box, "locked.png")
        let fine = try Self.published(box, "fine.png")
        let gone = try Self.published(box, "gone.png")
        try FileManager.default.removeItem(at: gone.url)
        let mover = Mover()
        mover.failing = ["locked.png"]
        let file = box.dir.appending(path: "undo.json")
        let history = UndoHistory(store: UndoStore(file: file), now: { UndoLogTests.start }, trash: mover.move)
        let batch = BatchID()
        await history.record(batch, outputs: [locked, fine, gone])
        let first = try #require(await history.undo(batch))
        #expect(first.trashed == [fine.url] && first.canRetry)
        #expect(UndoStore(file: file).load().entry(for: batch)?.outputs.map(\.url) == [locked.url])
        mover.failing = []
        let second = try #require(await history.undo(batch))
        #expect(second.trashed == [locked.url] && second.skipped.isEmpty && !second.canRetry)
        #expect(await history.undo(batch) == nil)
    }

    @Test func undoCopySaysWhatHappened() {
        let url = URL(fileURLWithPath: "/x/a.png")
        func skip(_ reason: UndoSkipReason) -> UndoSkip { UndoSkip(url: url, reason: reason) }
        #expect(UndoResult(trashed: [url], skipped: []).message == "Moved to the Trash.")
        #expect(
            UndoResult(trashed: [], skipped: [skip(.changed)]).message
                == "1 file changed since it was saved, so it was left in place.")
        #expect(
            UndoResult(trashed: [], skipped: [skip(.missing), skip(.missing)]).message
                == "2 files were no longer there.")
        #expect(
            UndoResult(trashed: [url], skipped: [skip(.missing), skip(.trashFailed)]).message
                == "1 file moved to the Trash. 1 file was no longer there. "
                + "1 file couldn't be moved to the Trash; Undo can try again.")
        #expect(
            UndoResult(trashed: [url, url], skipped: [skip(.changed), skip(.changed)]).message
                == "2 files moved to the Trash. 2 files changed since they were saved, so they were left in place.")
    }

    static func published(_ box: Sandbox, _ name: String) throws -> PublishedOutput {
        let url = try box.file(name, "abc")
        let stamp = try #require(FileStamp.read(url))
        return PublishedOutput(
            url: url, format: .png, byteCount: stamp.byteCount, fileID: stamp.fileID, modified: stamp.modified)
    }
}

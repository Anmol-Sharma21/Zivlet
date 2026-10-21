import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// One HUD for every batch (03a §4.5): which batch it shows, so a finished batch with failures is never replaced by
/// a newer one before the user has seen it, and buttons act on the batch on screen.
@Suite("HUD board: which batch the HUD shows")
struct HUDBoardTests {
    static func snapshot(_ batch: BatchID, _ states: [JobState], finished: Bool) -> BatchSnapshot {
        let items = states.enumerated().map { BatchItem(job: JobID(), name: "f\($0.offset).jpg", state: $0.element) }
        return BatchSnapshot(batch: batch, target: .png, items: items, isFinished: finished)
    }

    static let saved = JobState.succeeded(BatchPresentationTests.output)
    static let failed = JobState.failed(.diskFull)
    static let working = JobState.running(JobProgress(fraction: 0.5))

    @Test func aFinishedFailureStaysUntilDismissedThenTheNextBatchShows() {
        let (a, b) = (BatchID(), BatchID())
        let board = HUDBoard()
            .updating(Self.snapshot(a, [Self.failed], finished: true))
            .updating(Self.snapshot(b, [Self.working], finished: false))
        #expect(board.shown?.batch == a)
        let next = board.dismissing(a)
        #expect(next.shown?.batch == b && next.shown?.isFinished == false)
        #expect(next.dismissing(b).shown == nil)
    }

    @Test func aWorkingBatchReplacesAFinishedSuccess() {
        let (a, b) = (BatchID(), BatchID())
        let board = HUDBoard()
            .updating(Self.snapshot(a, [Self.saved], finished: true))
            .updating(Self.snapshot(b, [Self.working], finished: false))
        #expect(board.shown?.batch == b)
        #expect(board.updating(Self.snapshot(a, [Self.saved], finished: true)).shown?.batch == b)
    }

    @Test func theNewestWorkingBatchShowsAndEachBatchKeepsItsLatestSnapshot() {
        let (a, b) = (BatchID(), BatchID())
        let board = HUDBoard()
            .updating(Self.snapshot(a, [Self.working], finished: false))
            .updating(Self.snapshot(b, [Self.working], finished: false))
        #expect(board.shown?.batch == b)
        let bDone = board.updating(Self.snapshot(b, [Self.saved], finished: true))
        #expect(bDone.shown?.batch == a, "a success does not hide a batch still converting")
        let aFailed = bDone.updating(Self.snapshot(a, [Self.saved, Self.failed], finished: true))
        #expect(aFailed.shown?.batch == a && aFailed.shown?.failures.count == 1)
    }

    @Test func twoUnseenFailuresAreShownOldestFirst() {
        let (a, b) = (BatchID(), BatchID())
        let board = HUDBoard()
            .updating(Self.snapshot(a, [Self.failed], finished: true))
            .updating(Self.snapshot(b, [Self.failed], finished: true))
        #expect(board.shown?.batch == a)
        #expect(board.dismissing(a).shown?.batch == b)
    }

    @Test func aLingeringSuccessIsDismissedOnlyWhileItIsShown() {
        let (a, b) = (BatchID(), BatchID())
        let board = HUDBoard().updating(Self.snapshot(a, [Self.saved], finished: true))
        #expect(board.expiring(a).shown == nil)
        let busy = board.updating(Self.snapshot(b, [Self.working], finished: false))
        #expect(busy.expiring(a).shown?.batch == b)
    }
}

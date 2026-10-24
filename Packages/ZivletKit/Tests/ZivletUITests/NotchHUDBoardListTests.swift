import Foundation
import Testing
import ZivletActions
import ZivletCore
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Notch HUD board: several items, displays, announcements, redraw")
struct NotchHUDBoardListTests {
    let t0 = Duration.seconds(100)

    @Test func twoJobsShowTheCountAndACombinedRing() throws {
        let board = NotchHUDBoard()
            .updating(try HUDFx.running(JobProgress(fraction: 0.2)), display: 1, now: t0)
            .updating(try HUDFx.running(JobProgress(fraction: 0.6)), display: 1, now: t0)
        let tab = try #require(board.tab(on: 1))
        #expect(tab.count == "2 jobs" && !tab.failed && board.request(on: 1)?.resting == .collapsed)
        guard case .fraction(let mean) = tab.ring else { return #expect(Bool(false)) }
        #expect(abs(mean - 0.4) < 0.0001)
    }

    @Test func aFailureAmongSeveralMarksTheTabAndListsFirst() throws {
        let failed = try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom"))
        let board = NotchHUDBoard()
            .updating(try HUDFx.running(JobProgress(fraction: 0.2)), display: 1, now: t0)
            .updating(try HUDFx.running(JobProgress(fraction: 0.3)), display: 1, now: t0)
            .updating(failed, display: 1, now: t0)
        #expect(board.tab(on: 1)?.failed == true && board.tab(on: 1)?.count == "3 jobs")
        #expect(board.rows(on: 1).first?.id == .batch(failed.batch))
        #expect(board.rows(on: 1).first?.status == .failed)
        #expect(board.accessibilityValue(on: 1).contains("1 failed"))
    }

    @Test func severalFailuresAreRowsNotStackedCards() throws {
        let error = JobError.processFailed(status: 1, stderrTail: "boom")
        let board = NotchHUDBoard()
            .updating(try HUDFx.failed(error: error), display: 1, now: t0)
            .updating(try HUDFx.failed(error: error), display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .collapsed)
        #expect(board.rows(on: 1).map(\.status) == [.failed, .failed])
    }

    @Test func aRemovedDisplaysItemsMoveToItsReplacement() throws {
        let board = NotchHUDBoard()
            .updating(try HUDFx.running(JobProgress(fraction: 0.2)), display: 2, now: t0)
            .updating(try HUDFx.running(JobProgress(fraction: 0.2)), display: 1, now: t0)
            .movingItems(from: 2, to: 1)
        #expect(board.request(on: 2) == nil && board.tab(on: 1)?.count == "2 jobs")
        #expect(board.displays == [1])
    }

    @Test func aLaterSnapshotFindsItsItemOnTheReplacementDisplay() throws {
        let running = try HUDFx.running(JobProgress(fraction: 0.2))
        let job = try #require(running.items.first?.job)
        let later = running.applying(.changed(running.batch, job, .running(JobProgress(fraction: 0.7))))
        let board = NotchHUDBoard().updating(running, display: 2, now: t0).movingItems(from: 2, to: 1)
            .updating(later, display: 2, now: t0 + .seconds(1))
        #expect(board.request(on: 2) == nil && board.tab(on: 1)?.ring == .fraction(0.7))
    }

    @Test func theListShowsFiveRowsThenMore() throws {
        var board = NotchHUDBoard()
        for _ in 0..<7 { board = board.updating(try HUDFx.running(JobProgress(fraction: 0.1)), display: 1, now: t0) }
        #expect(board.rows(on: 1).count == 5 && board.moreLabel(on: 1) == "+2 more")
        #expect(NotchHUDBoard().moreLabel(on: 1) == nil)
    }

    @Test func eachRowLeavesByItsOwnRule() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        let board = NotchHUDBoard()
            .updating(try HUDFx.running(JobProgress(fraction: 0.1)), display: 1, now: t0)
            .updating(done, display: 1, now: t0)
        #expect(board.rows(on: 1).count == 2)
        let later = board.expiring(now: t0 + .seconds(4))
        #expect(later.rows(on: 1).count == 1 && later.rows(on: 1).first?.status == .working(0.1))
    }

    @Test func itemsAreKeptPerDisplay() throws {
        let board = NotchHUDBoard()
            .updating(try HUDFx.running(JobProgress(fraction: 0.1)), display: 1, now: t0)
            .updating(try HUDFx.running(JobProgress(fraction: 0.1)), display: 2, now: t0)
        #expect(board.tab(on: 1)?.count == nil && board.tab(on: 2)?.count == nil)
        #expect(board.request(on: 1)?.display == 1 && board.request(on: 2)?.display == 2)
    }

    @Test func announcesStartSavedFailedAndToastOnceButNeverPercentages() throws {
        let queued = try HUDFx.snapshot(submitted: 1)
        let start = NotchHUDBoard().updating(queued, display: 1, now: t0)
        #expect(start.announcements == [Announcement(text: "Converting to PNG, file0.heic", highPriority: false)])
        #expect(start.updating(queued, display: 1, now: t0).announcements.isEmpty)
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        let saved = start.updating(done, display: 1, now: t0)
        #expect(saved.announcements == [Announcement(text: "Saved photo.jpg", highPriority: false)])
        let failed = try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom"))
        let failure = saved.updating(failed, display: 1, now: t0).announcements
        #expect(failure.count == 1 && failure.first?.highPriority == true)
        #expect(failure.first?.text == BatchPresentation.make(failed).title)
        let toast = saved.updating(.done(toast: "Copied 1 file", undo: nil), display: 1, now: t0)
        #expect(toast.announcements == [Announcement(text: "Copied 1 file", highPriority: false)])
        #expect(toast.expiring(now: t0 + .seconds(1)).announcements.isEmpty)
    }

    @Test func progressRedrawsOnlyWhenThePercentChangesAtMostFourTimesASecond() throws {
        let running = try HUDFx.running(JobProgress(fraction: 0.4))
        let job = try #require(running.items.first?.job)
        func at(_ fraction: Double) -> BatchSnapshot {
            running.applying(.changed(running.batch, job, .running(JobProgress(fraction: fraction))))
        }
        let first = NotchHUDBoard().updating(running, display: 1, now: t0)
        #expect(first.redraw)
        let same = first.updating(at(0.401), display: 1, now: t0 + .milliseconds(50))
            .updating(at(0.402), display: 1, now: t0 + .milliseconds(100))
        #expect(!same.redraw)
        let soon = same.updating(at(0.41), display: 1, now: t0 + .milliseconds(100))
        #expect(!soon.redraw)
        #expect(soon.updating(at(0.41), display: 1, now: t0 + .milliseconds(260)).redraw)
    }

    @Test func aFinishAlwaysRedraws() throws {
        let running = try HUDFx.running(JobProgress(fraction: 0.4))
        let board = NotchHUDBoard().updating(running, display: 1, now: t0)
        let done = running.applying(.finished(running.batch))
        #expect(board.updating(done, display: 1, now: t0 + .milliseconds(10)).redraw)
    }

    // MARK: One line per row (plan 14 D16)

    private func mixed() throws -> NotchHUDBoard {
        NotchHUDBoard()
            .updating(try HUDFx.running(JobProgress(fraction: 0.4)), display: 1, now: t0)
            .updating(
                try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg),
                display: 1, now: t0
            )
            .updating(try HUDFx.failed(error: .diskFull), display: 1, now: t0)
    }

    @Test func eachRowIsOneLineWithAShortStatus() throws {
        let rows = try mixed().rows(on: 1)
        #expect(rows.map(\.summary) == ["Failed", "40%", "2.1 MB → 640 KB"])
        #expect(rows.map(\.line) == ["There isn't enough free disk space", "clip.mov → MP4", "Saved photo.jpg"])
    }

    @Test func rowPressesAreUnchanged() throws {
        let rows = try mixed().rows(on: 1)
        #expect(
            rows.map { NotchListRow.presses($0, offersUndo: false) } == [
                [.retry, .close], [.cancel], [.reveal, .open],
            ])
        let action = NotchHUDRow(id: .action(1), title: "Copied 1 file", detail: "", status: .action)
        #expect(NotchListRow.presses(action, offersUndo: true) == [.undo])
    }

    @Test func theSpokenListIsUnchanged() throws {
        let spoken = try mixed().accessibilityValue(on: 1)
        #expect(
            spoken
                == "3 jobs, 1 failed, There isn't enough free disk space., clip.mov, "
                + "Converting to MP4, clip.mov, 40%, Saved photo.jpg, photo.jpg, 2.1 MB to 640 KB")
    }
}

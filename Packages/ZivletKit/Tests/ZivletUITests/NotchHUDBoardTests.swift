import Foundation
import Testing
import ZivletActions
import ZivletCore
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Notch HUD board: one item (P2-116, design/19 §4.3)")
struct NotchHUDBoardTests {
    let t0 = Duration.seconds(100)

    @Test func aWorkingJobRestsCollapsedWithItsIconAndRing() throws {
        let board = NotchHUDBoard().updating(try HUDFx.running(JobProgress(fraction: 0.4)), display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .collapsed)
        #expect(board.request(on: 1)?.hoverSurface == .expanded && board.request(on: 1)?.client == .hud)
        let expected = TabContent(icon: .family(.video), ring: .fraction(0.4), count: nil, failed: false)
        #expect(board.tab(on: 1) == expected)
        #expect(board.nextDeadline == nil)
    }

    @Test func aJobOfUnknownLengthShowsTheSteppedGlyph() throws {
        let running = try HUDFx.running(JobProgress(fraction: nil, bytesWritten: 1_000))
        let board = NotchHUDBoard().updating(running, display: 1, now: t0)
        #expect(board.tab(on: 1)?.ring == .step(0))
        #expect(board.nextDeadline == t0 + NotchHUDBoard.stepInterval)
        let later = board.expiring(now: t0 + .milliseconds(250))
        #expect(later.tab(on: 1)?.ring == .step(1) && later.redraw)
        #expect(later.expiring(now: t0 + .milliseconds(2_250)).tab(on: 1)?.ring == .step(1))  // 9 steps: wraps at 8
    }

    @Test func aSavedJobShowsTheSavedToastForFourSeconds() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
        let board = NotchHUDBoard().updating(done, display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .toast)
        #expect(board.toastLine(on: 1) == "Saved photo.jpg · 2.1 MB → 640 KB")
        #expect(board.toastAccessibilityLabel(on: 1) == "Saved photo.jpg, 2.1 MB to 640 KB")
        #expect(board.toastGlyph(on: 1) == .saved)
        #expect(board.nextDeadline == t0 + .seconds(4))
        #expect(board.expiring(now: t0 + .seconds(4)).request(on: 1) == nil)
    }

    @Test func hoverHoldsTheToastAndLeavingRestartsTheFullLinger() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        var board = NotchHUDBoard().updating(done, display: 1, now: t0).holding(true, display: 1, now: t0 + .seconds(3))
        #expect(board.expiring(now: t0 + .seconds(30)).request(on: 1) != nil)
        board = board.holding(false, display: 1, now: t0 + .seconds(30))
        #expect(board.nextDeadline == t0 + .seconds(34))
    }

    @Test func aFailureShowsAToastThenWaitsInTheTabUntilClosed() throws {
        let failed = try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom"))
        let board = NotchHUDBoard().updating(failed, display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .toast && board.toastGlyph(on: 1) == .failed)
        #expect(board.request(on: 1)?.closable == true)
        let later = board.expiring(now: t0 + .seconds(4))
        #expect(later.request(on: 1)?.resting == .collapsed && later.tab(on: 1)?.failed == true)
        #expect(later.nextDeadline == nil)
        #expect(later.expiring(now: t0 + .seconds(600)).request(on: 1) != nil)
    }

    @Test func lingersAreThreeTimesAsLongWithAssistiveTech() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        let board = NotchHUDBoard(assistiveTech: true).updating(done, display: 1, now: t0)
        #expect(board.nextDeadline == t0 + .seconds(12))
        let copied = ActionResult.done(toast: "Copied 1 file", undo: nil)
        let toast = NotchHUDBoard().assisted(true).updating(copied, display: 1, now: t0)
        #expect(toast.nextDeadline == t0 + .milliseconds(4_500))
    }

    @Test func anActionToastLeavesAfter1500msOr4sWithUndo() {
        let plain = NotchHUDBoard().updating(.done(toast: "Copied 1 file", undo: nil), display: 1, now: t0)
        #expect(plain.nextDeadline == t0 + .milliseconds(1_500))
        #expect(plain.request(on: 1)?.resting == .toast && plain.toastGlyph(on: 1) == .action)
        let move = NotchHUDBoard().updating(.done(toast: "Moved 1 file", undo: BatchID()), display: 1, now: t0)
        #expect(move.nextDeadline == t0 + .seconds(4) && move.toastLine(on: 1) == "Moved 1 file")
        #expect(move.expiring(now: t0 + .seconds(4)).request(on: 1) == nil)
    }

    @Test func anActionToastStaysForTheUndoWindowItOffers() {
        let cleared = ActionResult.done(toast: "Cleared", undo: BatchID(), linger: .seconds(10))
        let board = NotchHUDBoard().updating(cleared, display: 1, now: t0)
        #expect(board.nextDeadline == t0 + .seconds(10) && cleared.linger == .seconds(10))
        #expect(board.expiring(now: t0 + .seconds(4)).request(on: 1) != nil)
        #expect(board.expiring(now: t0 + .seconds(10)).request(on: 1) == nil)
    }

    @Test func aFailedActionShowsItsTitleThenWaits() {
        let failed = NotchHUDBoard().updating(.failed(ActionCard(title: "Could not copy")), display: 1, now: t0)
        #expect(failed.toastLine(on: 1) == "Could not copy" && failed.toastGlyph(on: 1) == .failed)
        #expect(failed.expiring(now: t0 + .seconds(4)).tab(on: 1)?.failed == true)
    }

    @Test func aCancelledActionShowsNothing() {
        #expect(NotchHUDBoard().updating(ActionResult.cancelled, display: 1, now: t0).request(on: 1) == nil)
    }

    @Test func closingTheLastItemWithdrawsTheRequest() throws {
        let failed = try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom"))
        let board = NotchHUDBoard().updating(failed, display: 1, now: t0)
        #expect(board.closing(.batch(failed.batch), now: t0).request(on: 1) == nil)
        #expect(board.closingAll(on: 1).request(on: 1) == nil)
    }

    @Test func aResultWhileHeldDoesNotStartItsLinger() throws {
        let running = try HUDFx.running(JobProgress(fraction: 0.9), name: "photo.heic")
        let held = NotchHUDBoard().updating(running, display: 1, now: t0).holding(true, display: 1, now: t0)
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        let board = held.updating(done, display: 1, now: t0 + .seconds(1))
        #expect(board.request(on: 1)?.hoverSurface == .expanded && board.isHeld(on: 1))
        #expect(board.expiring(now: t0 + .seconds(60)).request(on: 1) != nil)
    }

    @Test func theEndOfADragRestartsTheFullLinger() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        let board = NotchHUDBoard().updating(done, display: 1, now: t0)
            .holding(true, display: 1, now: t0 + .seconds(1)).holding(false, display: 1, now: t0 + .seconds(9))
        #expect(board.nextDeadline == t0 + .seconds(13))
    }

    @Test func undoPausesTheLingerAndItsReplyRestartsIt() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        let paused = NotchHUDBoard().updating(done, display: 1, now: t0).pausing(.batch(done.batch))
        #expect(paused.nextDeadline == nil)
        #expect(paused.restarting(.batch(done.batch), now: t0 + .seconds(5)).nextDeadline == t0 + .seconds(9))
    }
}

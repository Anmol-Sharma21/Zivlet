import Foundation
import Testing
import ZivletCore
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Visible progress and the visible key (G-M5a-1, 19b §6.2)")
struct NotchVisibleTests {
    @Test func theKeyHoldsTheShortTimeLeftTheCardDraws() throws {
        let snapshot = try HUDFx.running(JobProgress(fraction: 0.4, eta: .seconds(40)))
        #expect(VisibleKey(snapshot, ringSteps: 84, barSteps: 100).shortTimeLeft == "< 1 min")
    }

    @Test func quantaFollowTheDrawnLengthInPixels() {
        #expect(VisibleProgress.steps(lengthInPoints: 50, scale: 2) == 100)
        #expect(VisibleProgress.steps(lengthInPoints: 50, scale: 1) == 50)
        #expect(VisibleProgress.steps(lengthInPoints: 10, scale: 2) == 20)
        #expect(VisibleProgress.steps(lengthInPoints: 300, scale: 2) == 100)
        #expect(VisibleProgress.steps(lengthInPoints: 0.2, scale: 1) == 1)
    }

    @Test func aChangeSmallerThanOneStepIsNotAChange() {
        #expect(VisibleProgress(0.401, steps: 100) == VisibleProgress(0.409, steps: 100))
        #expect(VisibleProgress(0.401, steps: 100) != VisibleProgress(0.411, steps: 100))
        #expect(VisibleProgress(0.41, steps: 50) == VisibleProgress(0.419, steps: 50))
        #expect(VisibleProgress(1.2, steps: 100).step == 100 && VisibleProgress(-1, steps: 100).step == 0)
        #expect(VisibleProgress(.nan, steps: 100).step == 0)
    }

    @Test func snapshotsThatDrawTheSameHaveTheSameKey() throws {
        let a = try HUDFx.running(JobProgress(fraction: 0.402, eta: .seconds(40)))
        let b = a.applyingProgress(JobProgress(fraction: 0.404, eta: .seconds(38)))
        #expect(VisibleKey(a, ringSteps: 100, barSteps: 100) == VisibleKey(b, ringSteps: 100, barSteps: 100))
    }

    @Test func aNewPercentANewTimeLeftOrANewFileChangesTheKey() throws {
        let a = try HUDFx.running(JobProgress(fraction: 0.402, eta: .seconds(40)))
        let key = VisibleKey(a, ringSteps: 100, barSteps: 100)
        let percent = a.applyingProgress(JobProgress(fraction: 0.41, eta: .seconds(40)))
        let time = a.applyingProgress(JobProgress(fraction: 0.402, eta: .seconds(90)))
        #expect(VisibleKey(percent, ringSteps: 100, barSteps: 100) != key)
        #expect(VisibleKey(time, ringSteps: 100, barSteps: 100) != key)
        let two = try HUDFx.snapshot(submitted: 2, target: .png)
        let first = try #require(two.items.first?.job)
        let second = try #require(two.items.last?.job)
        let output = PublishedOutput(
            url: .init(filePath: "/tmp/file0.png"), format: .png, byteCount: 1, fileID: 1, modified: .distantPast)
        let onFirst = two.applying(.changed(two.batch, first, .running(JobProgress(fraction: 0.5))))
        let onSecond = onFirst.applying(.changed(two.batch, first, .succeeded(output)))
            .applying(.changed(two.batch, second, .running(JobProgress(fraction: 0))))
        #expect(
            VisibleKey(onFirst, ringSteps: 100, barSteps: 100) != VisibleKey(onSecond, ringSteps: 100, barSteps: 100))
    }

    @Test func bytesWrittenOfAJobOfUnknownLengthAreVisible() throws {
        let a = try HUDFx.running(JobProgress(fraction: nil, bytesWritten: 3_400_000))
        let same = a.applyingProgress(JobProgress(fraction: nil, bytesWritten: 3_400_100))
        let more = a.applyingProgress(JobProgress(fraction: nil, bytesWritten: 9_000_000))
        #expect(VisibleKey(a, ringSteps: 100, barSteps: 100) == VisibleKey(same, ringSteps: 100, barSteps: 100))
        #expect(VisibleKey(a, ringSteps: 100, barSteps: 100) != VisibleKey(more, ringSteps: 100, barSteps: 100))
    }

    @Test func finishingAlwaysChangesTheKey() throws {
        let running = try HUDFx.running(JobProgress(fraction: 0.999))
        let job = try #require(running.items.first?.job)
        let finished = running.applying(.changed(running.batch, job, .failed(.diskFull))).applying(
            .finished(running.batch))
        #expect(
            VisibleKey(running, ringSteps: 100, barSteps: 100) != VisibleKey(finished, ringSteps: 100, barSteps: 100))
        let saved = try HUDFx.finished(outputs: [("clip.png", before: 2, after: 1)])
        #expect(VisibleKey(saved, ringSteps: 100, barSteps: 100) != VisibleKey(finished, ringSteps: 100, barSteps: 100))
    }
}

/// The board's redraw rule (19b §6.2): the collapsed tab redraws at the ring's step; an open card or list at every
/// change of what it shows; both at most every 250 ms, and a change held back by that floor has a deadline.
@Suite("Notch HUD board: what redraws and when")
struct NotchHUDBoardRedrawTests {
    private static func running(_ fraction: Double) throws -> BatchSnapshot {
        try HUDFx.running(JobProgress(fraction: fraction, eta: .seconds(40)))
    }

    @Test func aPercentTheRingCannotShowRedrawsOnlyAnOpenIsland() throws {
        let first = try Self.running(0.405)
        let next = first.applyingProgress(JobProgress(fraction: 0.411, eta: .seconds(40)))
        let collapsed = NotchHUDBoard().updating(first, display: 1, now: .zero)
        #expect(!collapsed.updating(next, display: 1, now: .milliseconds(300)).redraw)
        let open = collapsed.showing(.expanded, on: 1, now: .milliseconds(10))
        #expect(open.redraw)  // opening draws the latest at once
        #expect(open.updating(next, display: 1, now: .milliseconds(300)).redraw)
        let closed = open.showing(.collapsed, on: 1, now: .milliseconds(20))
        #expect(!closed.updating(next, display: 1, now: .milliseconds(300)).redraw)
    }

    @Test func aChangeHeldBackByTheFloorHasADeadline() throws {
        let first = try Self.running(0.40)
        let board = NotchHUDBoard().updating(first, display: 1, now: .zero)
            .updating(
                first.applyingProgress(JobProgress(fraction: 0.43, eta: .seconds(40))), display: 1,
                now: .milliseconds(100))
        #expect(!board.redraw && board.nextDeadline == .milliseconds(250))
        let woken = board.expiring(now: .milliseconds(250))
        #expect(woken.redraw && woken.nextDeadline == nil)
    }
}

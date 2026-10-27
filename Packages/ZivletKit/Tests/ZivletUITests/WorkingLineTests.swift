import AppKit
import NotchTestSupport
import Testing
import ZivletActions
import ZivletCore
import ZivletNotch
import ZivletNotchCore

@testable import ZivletUI

@Suite("A long action's working line (P2-104): working, never done, cancellable, and replaced in one step")
@MainActor
struct WorkingLineTests {
    static let point = CGPoint(x: -5_000, y: -5_000)

    static func status(_ line: String, _ fraction: Double? = nil) -> WorkingStatus {
        WorkingStatus(line: line, fraction: fraction, symbol: "text.viewfinder")
    }

    final class Presses {
        var cancels = 0
    }

    @Test func aCancelledResultHidesTheHUDsWorkingLine() {
        let hud = ActionHUD()
        defer { hud.hide() }
        hud.showWorking(Self.status("Recognising text…"), near: Self.point) {}
        hud.show(.cancelled, near: Self.point)
        #expect(hud.model.result == nil)
    }

    @Test func aCancelledResultLeavesAFinishedResultAlone() {
        let hud = ActionHUD()
        defer { hud.hide() }
        hud.show(.text(TextFx.outcome()), near: Self.point)
        hud.show(.cancelled, near: Self.point)
        #expect(hud.model.result?.text != nil)
    }

    @Test func theHUDsWorkingLineStaysAndItsCancelStopsTheJob() {
        let hud = ActionHUD()
        defer { hud.hide() }
        let presses = Presses()
        hud.showWorking(Self.status("Recognising text… 40%", 0.4), near: Self.point) { presses.cancels += 1 }
        #expect(!hud.hideIsScheduled)
        #expect(hud.model.result?.working?.fraction == 0.4)
        hud.cancelWorking()
        #expect(presses.cancels == 1)
        #expect(hud.model.result == nil)
        hud.cancelWorking()
        #expect(presses.cancels == 1)
    }

    @Test func theIslandDrawsTheWorkingItemAsWorking() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.showWorking(Self.status("Preparing text recognition (one time)…"), near: NotchRig.onNotch) {}
        #expect(rig.hud.board.tab(on: 1)?.ring != .done)
        #expect(rig.hud.board.tab(on: 1)?.icon == .symbol("text.viewfinder"))
        #expect(rig.hud.board.toastGlyph(on: 1) == .working)
        #expect(rig.hud.board.request(on: 1)?.closable == false)
        #expect(rig.hud.board.request(on: 1)?.resting == .toast)
        #expect(rig.hud.board.nextDeadline != nil)  // the stepped glyph moves; no linger runs out
    }

    @Test func theIslandsToastFollowsTheNewestLineAndItsRing() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.showWorking(Self.status("Preparing text recognition (one time)…"), near: NotchRig.onNotch) {}
        rig.hud.showWorking(Self.status("Recognising text… 50%", 0.5), near: NotchRig.onNotch) {}
        #expect(rig.hud.board.toastLine(on: 1) == "Recognising text… 50%")
        #expect(rig.hud.board.tab(on: 1)?.ring == .fraction(0.5))
        #expect(rig.hud.board.ordered(on: 1).count == 1)
    }

    @Test func theResultTakesTheWorkingItemsPlaceInOneBoardChange() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.showWorking(Self.status("Recognising text… 50%", 0.5), near: NotchRig.onNotch) {}
        var changes = 0
        rig.hud.onApply = { changes += 1 }
        rig.hud.show(.text(TextFx.outcome()), near: NotchRig.onNotch)
        #expect(changes == 1)
        #expect(rig.hud.board.ordered(on: 1).count == 1)
        #expect(rig.hud.board.toastGlyph(on: 1) == .action)
    }

    @Test func theIslandsCancelStopsTheJobAndRemovesTheItem() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let presses = Presses()
        rig.hud.showWorking(Self.status("Recognising text…"), near: NotchRig.onNotch) { presses.cancels += 1 }
        rig.hud.press(.cancel, onItem: .action(0))
        #expect(presses.cancels == 1)
        #expect(rig.hud.board.ordered(on: 1).isEmpty)
        rig.hud.show(.cancelled, near: NotchRig.onNotch)  // the job's own cancelled result then shows nothing
        #expect(rig.hud.board.ordered(on: 1).isEmpty)
    }

    @Test func aWorkingActionInTheListIsARunningRowWithCancel() {
        let working = ActionResult.working(Self.status("Recognising text… 40%", 0.4))
        let board = NotchHUDBoard().updating(working, display: 1, now: .zero)
            .updating(.done(toast: "Copied", undo: nil), display: 1, now: .zero)
        let row = board.rows(on: 1).first
        #expect(row?.status == .working(0.4))
        #expect(row.map { NotchListRow.presses($0, offersUndo: false) } == [.cancel])
        #expect(board.tab(on: 1)?.ring == .fraction(0.4))
    }

    @Test func theFirstPageEndsThePreparingLine() {
        #expect(ToolWiringModel.workingLine(warmupDone: false, fraction: 0.4) == "Recognising text… 40%")
        let status = ToolWiringModel.working(warmupDone: false, fraction: nil)
        #expect(status.line == ToolWiringModel.preparing && status.fraction == nil)
    }

    @Test func aWorkingResultHasTheLineAsItsToastAndNothingElse() {
        let result = ActionResult.working(Self.status("Recognising text…"))
        #expect(result.toast == "Recognising text…")
        #expect(result.card == nil && result.undo == nil && result.text == nil && result.linger == nil)
        #expect(result.listing(lines: ["x"]) == result)
    }
}

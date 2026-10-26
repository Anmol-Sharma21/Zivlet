import AppKit
import Testing
import ZivletActions
import ZivletCore

@testable import ZivletUI

@Suite("Action HUD: toasts leave, Undo runs once (03b §7)")
@MainActor
struct ActionHUDTests {
    static let toast = ActionResult.done(toast: "Copied 1 file", undo: nil)

    /// Close while the pointer is inside sends no exit event (the panel is ordered out), so the hover flag must not
    /// outlive the toast: the next toast still leaves on its own.
    @Test func aToastClosedWhileHoveredDoesNotPinTheNextOne() {
        let hud = ActionHUD()
        hud.show(.failed(ActionCard(title: "Zivlet couldn't move 1 file.")), near: nil)
        hud.hover(true)
        hud.hide()
        hud.show(Self.toast, near: nil)
        #expect(hud.hideIsScheduled && !hud.hovering)
        hud.hide()
    }

    @Test func aNewToastWhileHoveredStillLeaves() {
        let hud = ActionHUD()
        hud.show(Self.toast, near: nil)
        hud.hover(true)
        #expect(!hud.hideIsScheduled)
        hud.show(.done(toast: "Copied the path", undo: nil), near: nil)
        #expect(hud.hideIsScheduled)
        hud.hide()
    }

    @Test func undoIsAskedOnceWhileItsReplyIsPending() async {
        let hud = ActionHUD()
        let batch = BatchID()
        var asked = 0
        hud.onUndo = { _ in
            asked += 1
            try? await Task.sleep(for: .milliseconds(30))
            return UndoReply(message: "Moved 1 file back.", canRetry: false)
        }
        hud.show(.done(toast: "Moved 1 file", undo: batch), near: nil)
        #expect(hud.model.offersUndo)
        hud.undo()
        hud.undo()
        #expect(!hud.model.offersUndo)
        await hud.pendingUndo?.value
        #expect(asked == 1 && hud.model.undoMessage == "Moved 1 file back." && !hud.model.offersUndo)
        #expect(hud.hideIsScheduled)
        hud.hide()
    }

    @Test func undoStaysWhenTheTrashRefusedSomething() async {
        let hud = ActionHUD()
        hud.onUndo = { _ in UndoReply(message: "1 file could not be moved back.", canRetry: true) }
        hud.show(.done(toast: "Moved 1 file", undo: BatchID()), near: nil)
        hud.undo()
        await hud.pendingUndo?.value
        #expect(hud.model.offersUndo)
        hud.hide()
    }

    @Test func aToastLingersForItsOwnUndoWindow() {
        #expect(ActionHUD.linger(for: Self.toast) == ActionHUD.toastLinger)
        #expect(ActionHUD.linger(for: .done(toast: "Moved 1 item", undo: BatchID())) == ActionHUD.undoLinger)
        let cleared = ActionResult.done(toast: "Cleared", undo: BatchID(), linger: .seconds(10))
        #expect(ActionHUD.linger(for: cleared) == .seconds(10))
    }

    @Test func thePanelIsTheKeyableHUDWindow() {
        #expect(ActionHUD().canBecomeKey)
    }
}

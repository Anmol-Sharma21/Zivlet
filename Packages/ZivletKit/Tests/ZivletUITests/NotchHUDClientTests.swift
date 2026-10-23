import AppKit
import NotchTestSupport
import SwiftUI
import Testing
import ZivletActions
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Notch HUD: actions, accessibility, displays and the presenter protocols")
@MainActor
struct NotchHUDClientTests {
    @Test func anActionToastUsesTheIslandAndLeaves() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.show(.done(toast: "Copied 1 file", undo: nil), near: NotchRig.onNotch)
        #expect(rig.hosts.surface(on: 1) == .toast && rig.hud.board.toastLine(on: 1) == "Copied 1 file")
        await rig.clock.advance(by: .milliseconds(1_500))
        await rig.settled()
        #expect(rig.hosts.surface(on: 1) == .hidden)
    }

    @Test func aCancelledActionShowsNothing() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.show(.cancelled, near: nil)
        #expect(rig.hosts.visibleDisplays.isEmpty)
    }

    @Test func anActionUndoIsAskedOnceAndItsCardCloses() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let batch = BatchID()
        var asked: [BatchID] = []
        rig.hud.onUndo = {
            asked.append($0)
            return UndoReply(message: "Moved 1 file back.", canRetry: false)
        }
        rig.hud.show(.done(toast: "Moved 1 file", undo: batch), near: nil)
        let id = try #require(rig.hud.board.rows(on: 1).first?.id)
        rig.hud.press(.undo, onItem: id)
        rig.hud.press(.undo, onItem: id)
        await rig.hud.pendingUndo(id)?.value
        #expect(asked == [batch] && rig.hud.actionModel(id)?.undoMessage == "Moved 1 file back.")
        rig.hud.press(.close, onItem: id)
        #expect(rig.hud.board.displays.isEmpty)
    }

    @Test func theIslandSpeaksItsLabelValueAndAction() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.show(try HUDFx.running(JobProgress(fraction: 0.4)))
        #expect(rig.hud.accessibilityLabel(display: 1) == "Zivlet progress and results")
        #expect(rig.hud.accessibilityValue(display: 1).hasPrefix("Converting to MP4, clip.mov, 40%"))
        #expect(rig.hud.accessibilityActionName == "Show Progress and Results")
        rig.hud.accessibilityActionPerformed(display: 1)
        #expect(rig.hosts.surface(on: 1) == .expanded)
    }

    @Test func aRemovedDisplaysItemsMoveToTheFirstDisplay() async throws {
        let rig = try NotchRig.both()
        defer { rig.hosts.close() }
        rig.hud.prepare(near: NotchRig.onPlain)
        rig.hud.show(try HUDFx.running(JobProgress(fraction: 0.4)))
        rig.displays.set([try OffscreenDisplays.notch()])
        await ManualClock.settle()
        #expect(rig.hud.board.displays == [1] && rig.hosts.surface(on: 1) == .collapsed)
    }

    @Test func everySurfaceDrawsSomething() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let failed = try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom"))
        let saved = try HUDFx.finished(outputs: [("photo.jpg", before: 2, after: 1)], target: .jpg)
        for snapshot in [try HUDFx.running(JobProgress(fraction: nil, bytesWritten: 9)), saved, failed] {
            rig.hud.show(snapshot)
            for surface in [IslandSurface.collapsed, .toast, .expanded] {
                #expect(Self.height(rig.hud.content(for: surface, display: 1)) > 0)
            }
            rig.hud.close(snapshot.batch)
        }
        rig.hud.show(
            .partial(toast: "Copied 1 file", card: ActionCard(title: "1 file was skipped"), undo: nil), near: nil)
        rig.hud.show(saved)
        rig.hud.show(failed)
        #expect(Self.height(rig.hud.content(for: .expanded, display: 1)) > 0)
        #expect(Self.height(rig.hud.content(for: .collapsed, display: 1)) > 0)
    }

    @Test func resultHUDRetryNoLongerQueuesItsOwnAnchor() throws {
        let screen = CGRect(x: -5000, y: -5000, width: 1440, height: 900)
        let hud = ResultHUD(screens: { [screen] })
        var retried: [(BatchID, CGPoint?)] = []
        hud.onRetry = { retried.append(($0, $1)) }
        let failed = try HUDFx.failed(error: .stalled)
        hud.prepare(near: CGPoint(x: -4000, y: -4500))
        hud.show(failed)
        hud.press(.retry, on: failed.batch)
        #expect(retried.count == 1 && retried.first?.0 == failed.batch && retried.first?.1 != nil)
        let next = try HUDFx.snapshot(submitted: 1)
        hud.show(next)
        #expect(hud.panelFrames == [HUDLayout.frame(anchor: nil, index: 0, screen: screen)])
        hud.close(next.batch)
    }

    @Test func resultHUDAndActionHUDStillWorkThroughTheProtocols() throws {
        let presenter: any HUDPresenter = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        presenter.prepare(near: nil)
        let snapshot = try HUDFx.snapshot(submitted: 1)
        presenter.show(snapshot)
        #expect((presenter as? ResultHUD)?.isVisible == true)
        presenter.close(snapshot.batch)
        let actions: any ActionPresenter = ActionHUD()
        actions.show(.done(toast: "Copied 1 file", undo: nil), near: nil)
        #expect((actions as? ActionHUD)?.hideIsScheduled == true)
        (actions as? ActionHUD)?.hide()
    }

    private static func height(_ view: AnyView) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: IslandLayout.Metrics.expandedWidth))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }
}

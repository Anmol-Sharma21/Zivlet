import AppKit
import NotchTestSupport
import Testing
import ZivletActions
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletUI

/// Hosts and a Notch HUD on off-screen displays, as the app builds them, with a clock the test moves.
@MainActor
struct NotchRig {
    let displays: FakeDisplayProvider
    let clock = ManualClock()
    let hosts: IslandHosts
    let hud: NotchHUD
    /// Inside the notch display (id 1) and the plain one (id 2).
    static let onNotch = CGPoint(x: -4_500, y: -4_500)
    static let onPlain = CGPoint(x: -6_500, y: 400)

    init(_ displays: FakeDisplayProvider) {
        self.displays = displays
        hosts = IslandHosts(provider: displays, clock: clock, animation: .instant)
        hud = NotchHUD(hosts: hosts, provider: displays, clock: clock)
    }

    static func both() throws -> NotchRig { NotchRig(try FakeDisplayProvider.notchAndExternal()) }
    static func notch() throws -> NotchRig { NotchRig(try FakeDisplayProvider.notchOnly()) }

    func settled(_ display: UInt32 = 1) async {
        await ManualClock.settle()
        await hosts.host(on: display)?.animationsSettled()
    }
}

@Suite("Notch HUD presenter (P2-116)")
@MainActor
struct NotchHUDTests {
    @Test func theIslandOpensOnTheDisplayOfTheDrop() throws {
        let rig = try NotchRig.both()
        defer { rig.hosts.close() }
        rig.hud.prepare(near: NotchRig.onPlain)
        rig.hud.show(try HUDFx.snapshot(submitted: 1))
        #expect(rig.hosts.visibleDisplays == [2])
        #expect(rig.hosts.surface(on: 2) == .collapsed)
    }

    @Test func aBatchNobodyPreparedOpensOnTheFirstDisplay() throws {
        let rig = try NotchRig.both()
        defer { rig.hosts.close() }
        rig.hud.show(try HUDFx.snapshot(submitted: 1))
        #expect(rig.hosts.visibleDisplays == [1])
    }

    @Test func cancelInTheIslandCancelsItsOwnBatch() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        var cancelled: [BatchID] = []
        rig.hud.onCancel = { cancelled.append($0) }
        let snapshot = try HUDFx.running(JobProgress(fraction: 0.2))
        rig.hud.show(snapshot)
        rig.hud.press(.cancel, on: snapshot.batch)
        #expect(cancelled == [snapshot.batch])
    }

    @Test func aSavedResultShowsItsToastAndLeavesAfterItsLinger() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.show(try HUDFx.finished(outputs: [("photo.jpg", before: 2_000, after: 1_000)], target: .jpg))
        #expect(rig.hosts.surface(on: 1) == .toast)
        await rig.clock.advance(by: .seconds(4))
        await rig.settled()
        #expect(rig.hosts.surface(on: 1) == .hidden && rig.hosts.visibleDisplays.isEmpty)
    }

    @Test func holdingTheIslandKeepsTheToastAndLeavingRestartsTheLinger() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.show(try HUDFx.finished(outputs: [("photo.jpg", before: 2, after: 1)], target: .jpg))
        rig.hud.held(true, display: 1, now: rig.clock.now())
        await rig.clock.advance(by: .seconds(10))
        #expect(rig.hosts.surface(on: 1) != .hidden)
        rig.hud.held(false, display: 1, now: rig.clock.now())
        await rig.clock.advance(by: .seconds(4))
        await rig.settled()
        #expect(rig.hosts.surface(on: 1) == .hidden)
    }

    @Test func aFailureWaitsInTheTabUntilEscapeClosesIt() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        var announced: [Announcement] = []
        rig.hud.announce = { announced.append($0) }
        let failed = try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom"))
        rig.hud.show(failed)
        #expect(announced.map(\.highPriority) == [true])
        await rig.clock.advance(by: .seconds(4))
        #expect(rig.hosts.surface(on: 1) == .collapsed)
        rig.hud.closeRequested(display: 1)
        await rig.settled()
        #expect(rig.hosts.surface(on: 1) == .hidden)
    }

    @Test func undoIsAskedOnceWhileItsReplyIsPending() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        var asked = 0
        rig.hud.onUndo = { _ in
            asked += 1
            try? await Task.sleep(for: .milliseconds(30))
            return UndoReply(message: "Moved 1 file to the Trash.", canRetry: false)
        }
        let snapshot = try HUDFx.finished(outputs: [("photo.png", before: 2, after: 1)])
        rig.hud.show(snapshot)
        rig.hud.press(.undo, on: snapshot.batch)
        rig.hud.press(.undo, on: snapshot.batch)
        #expect(rig.hud.board.nextDeadline == nil)
        await rig.hud.pendingUndo(.batch(snapshot.batch))?.value
        #expect(asked == 1 && rig.hud.card(snapshot.batch)?.undoMessage == "Moved 1 file to the Trash.")
        #expect(rig.hud.board.nextDeadline != nil)
    }

    @Test func revealOpenAndCopySkipOutputsAnUndoTrashed() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let snapshot = try HUDFx.finished(outputs: [("a.png", before: 2, after: 1), ("b.png", before: 2, after: 1)])
        let (first, second) = (snapshot.outputs[0].url, snapshot.outputs[1].url)
        rig.hud.onUndo = { _ in UndoReply(message: "1 file could not be moved.", canRetry: true, removed: [first]) }
        var acted: [[URL]] = []
        rig.hud.onReveal = { acted.append($0) }
        rig.hud.onOpen = { acted.append($0) }
        rig.hud.onCopy = { acted.append($0) }
        rig.hud.show(snapshot)
        rig.hud.press(.undo, on: snapshot.batch)
        await rig.hud.pendingUndo(.batch(snapshot.batch))?.value
        for press in [NotchHUD.Press.reveal, .open, .copy] { rig.hud.press(press, on: snapshot.batch) }
        #expect(acted == [[second], [second], [second]])
    }

    @Test func retryReportsTheSourceBatchAndItsDropPoint() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        var retried: [(BatchID, CGPoint?)] = []
        rig.hud.onRetry = { retried.append(($0, $1)) }
        let failed = try HUDFx.failed(error: .stalled)
        rig.hud.prepare(near: NotchRig.onNotch)
        rig.hud.show(failed)
        rig.hud.press(.retry, on: failed.batch)
        #expect(retried.count == 1 && retried.first?.0 == failed.batch && retried.first?.1 == NotchRig.onNotch)
        await rig.settled()
        #expect(rig.hosts.surface(on: 1) == .hidden)
    }

    @Test func showDetailsAndCloseActOnTheirOwnCard() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let failed = try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom"))
        rig.hud.show(failed)
        rig.hud.press(.showDetails, on: failed.batch)
        #expect(rig.hud.card(failed.batch)?.showsDetails == true)
        rig.hud.close(failed.batch)
        #expect(rig.hud.card(failed.batch) == nil && rig.hud.board.displays.isEmpty)
    }
}

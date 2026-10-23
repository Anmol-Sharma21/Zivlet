import AppKit
import NotchTestSupport
import Testing
import ZivletActions
import ZivletCore
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletNotch
@testable import ZivletUI

@Suite("Notch HUD: no display, spoken progress, the menu command and drags")
@MainActor
struct NotchHUDReachTests {
    @Test func withNoDisplayTheHUDCannotShowAndFilesNothingUnderAMadeUpID() throws {
        let rig = NotchRig(FakeDisplayProvider([]))
        defer { rig.hosts.close() }
        #expect(!rig.hud.canShow)
        rig.hud.show(try HUDFx.running(JobProgress(fraction: 0.4)))
        rig.hud.show(.done(toast: "Copied 1 file", undo: nil), near: nil)
        #expect(rig.hud.board.displays.isEmpty && !rig.hosts.hasItems)
    }

    @Test func withADisplayTheHUDCanShow() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        #expect(rig.hud.canShow)
    }

    @Test func theCollapsedIslandsSpokenValueFollowsProgress() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        let first = try HUDFx.running(JobProgress(fraction: 0.1))
        rig.hud.show(first)
        #expect(rig.hosts.host(on: 1)?.accessibilityValue.contains("10%") == true)
        await rig.clock.advance(by: .seconds(1))
        let job = try #require(first.items.first?.job)
        rig.hud.show(first.applying(.changed(first.batch, job, .running(JobProgress(fraction: 0.6)))))
        #expect(rig.hosts.host(on: 1)?.accessibilityValue.contains("60%") == true)
    }

    @Test func aResultOpenedByTheMenuCommandStaysUntilTheKeyboardGoesBack() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.show(try HUDFx.finished(outputs: [("photo.jpg", before: 2, after: 1)], target: .jpg))
        await rig.clock.advance(by: .seconds(3))
        rig.hosts.expandRequested()
        await rig.clock.advance(by: .seconds(10))
        #expect(rig.hosts.surface(on: 1) == .expanded && rig.hud.board.isHeld(on: 1))
    }

    @Test func aDragOfTheThumbnailHoldsTheIslandUntilItEnds() async throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.show(try HUDFx.finished(outputs: [("photo.jpg", before: 2, after: 1)], target: .jpg))
        let host = try #require(rig.hosts.host(on: 1))
        host.trackingEntered()
        await rig.clock.advance(by: .milliseconds(200))
        rig.hud.dragChanged(true, display: 1)
        host.trackingExited()
        await rig.clock.advance(by: .seconds(10))
        #expect(rig.hosts.surface(on: 1) == .expanded && rig.hud.board.isHeld(on: 1))
        rig.hud.dragChanged(false, display: 1)
        await rig.clock.advance(by: .milliseconds(300))
        #expect(rig.hosts.surface(on: 1) == .toast && !rig.hud.board.isHeld(on: 1))
    }

    @Test func aRouteToTheNotchFallsBackNearTheDropWhenTheIslandHasNoDisplay() {
        #expect(HUDRoute.notch.usable(islandHasDisplay: false) == .nearDrop)
        #expect(HUDRoute.notch.usable(islandHasDisplay: true) == .notch)
        #expect(HUDRoute.nearDrop.usable(islandHasDisplay: false) == .nearDrop)
    }
}

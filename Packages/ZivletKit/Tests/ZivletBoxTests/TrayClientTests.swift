import AppKit
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletTrigger

@testable import ZivletBox

@Suite("Tray client (P2-143, D-M5b-8, D-M5b-17)")
@MainActor
struct TrayClientTests {
    @Test func aDragRestingAtTheNotchOpensTheDropTarget() throws {
        let rig = try TrayRig(boxItems: 12)
        #expect(rig.hosts.surface(on: 1) == .sensor)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .dropTarget && rig.hosts.activeClient(on: 1) == .tray)
        #expect(rig.tray.accessibilityValue(display: 1) == "Add 3 items to the Drop Box")
    }

    @Test func leavingGoesBackToTheSensorWhileTheBoxHasItems() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        rig.tray.proximity(.left(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .sensor)
    }

    @Test func anEmptyBoxLeavesNothingAtTheNotch() throws {
        let rig = try TrayRig(boxItems: 0)
        #expect(rig.hosts.surface(on: 1) == .hidden)
        rig.tray.proximity(.entered(display: 1), itemCount: 2)
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
        rig.tray.proximity(.left(display: 1), itemCount: 2)
        #expect(rig.hosts.surface(on: 1) == .hidden)
    }

    @Test func theEndOfTheDragGoesBackToRest() throws {
        let rig = try TrayRig(boxItems: 4)
        rig.tray.proximity(.entered(display: 1), itemCount: 1)
        rig.tray.dragEnded()
        #expect(rig.hosts.surface(on: 1) == .sensor)
    }

    @Test func theWheelWinsAndTheTrayWaitsForANewApproach() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
        rig.tray.wheelShown()
        #expect(rig.hosts.surface(on: 1) == .sensor)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .sensor)
        rig.tray.wheelHidden()
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
    }

    @Test func withTheSettingOffThereIsNoDropTargetButTheSensorRests() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.opensWhileDragging = false
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .sensor)
    }

    @Test func aPillDisplayNeverGetsASensorButTakesADrop() throws {
        let rig = try TrayRig(boxItems: 12)
        #expect(rig.hosts.surface(on: 2) == .hidden && rig.hosts.activeClient(on: 2) == nil)
        rig.tray.proximity(.entered(display: 2), itemCount: 1)
        #expect(rig.hosts.surface(on: 2) == .dropTarget)
        rig.tray.proximity(.left(display: 2), itemCount: 1)
        #expect(rig.hosts.surface(on: 2) == .hidden && rig.hosts.activeClient(on: 2) == nil)
    }

    @Test func aLeaveFromAnotherDisplayDoesNotCloseTheDropTarget() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        rig.tray.proximity(.left(display: 2), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
    }

    @Test func movingToAnotherDisplaysZoneMovesTheDropTarget() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        rig.tray.proximity(.entered(display: 2), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .sensor && rig.hosts.surface(on: 2) == .dropTarget)
    }

    @Test func anUnknownDisplayIsIgnored() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 99), itemCount: 3)
        #expect(rig.tray.dropTarget == nil)
    }

    @Test func theRestFollowsTheBox() throws {
        let rig = try TrayRig(boxItems: 0)
        rig.box.count = 2
        rig.tray.boxChanged()
        #expect(rig.hosts.surface(on: 1) == .sensor)
        rig.box.count = 0
        rig.tray.boxChanged()
        #expect(rig.hosts.surface(on: 1) == .hidden)
    }

    @Test func theTrayAtRestNeverHidesTheHUDsTab() throws {
        let rig = try TrayRig(boxItems: 12)
        let hud = IslandRequest(client: .hud, display: 1, resting: .collapsed, hoverSurface: .expanded)
        rig.hosts.request(hud, from: .hud)
        #expect(rig.hosts.activeClient(on: 1) == .hud && rig.hosts.surface(on: 1) == .collapsed)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.activeClient(on: 1) == .tray && rig.hosts.surface(on: 1) == .dropTarget)
        rig.tray.dragEnded()
        #expect(rig.hosts.activeClient(on: 1) == .hud)
    }

    @Test func itSpeaksTheBoxAndOpensThePanelFromTheAction() throws {
        let rig = try TrayRig(boxItems: 12)
        #expect(rig.tray.accessibilityLabel(display: 1) == "Drop Box")
        #expect(rig.tray.accessibilityValue(display: 1) == "Drop Box, 12 items, 12 megabytes")
        #expect(rig.tray.accessibilityActionName == "Open Drop Box")
        rig.tray.accessibilityActionPerformed(display: 1)
        let island = try #require(rig.hosts.host(on: 1)).frame
        #expect(rig.box.panels == [.below(Rect2D(island))])
    }

    @Test func compactViewPressesReachTheBoxAndOpenPanelOpensBelowTheIsland() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.pressed(.share, display: 1)
        #expect(rig.box.presses == [.share])
        rig.tray.pressed(.openPanel, display: 1)
        #expect(rig.box.panels.count == 1 && rig.box.presses == [.share])
    }

    @Test func aRemovedDisplayForgetsItsDropTarget() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 2), itemCount: 3)
        rig.tray.displaysChanged([1], replacing: [2: 1])
        #expect(rig.tray.dropTarget == nil)
    }

    @Test func everySurfaceHasContent() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        for surface in IslandSurface.allCases { _ = rig.tray.content(for: surface, display: 1) }
        rig.tray.held(true, display: 1, now: .zero)
        rig.tray.closeRequested(display: 1)
    }
}

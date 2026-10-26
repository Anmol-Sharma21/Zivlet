import AppKit
import NotchTestSupport
import TestSupport
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletShelfCore
import ZivletTrigger

@testable import ZivletBox

@Suite("Tray drop, toast and compact view (P2-143, NB7)")
@MainActor
struct TrayDropTests {
    private func files(_ rig: BoxRig, _ count: Int) throws -> [URL] {
        try (0..<count).map { try rig.dir.file("tray-\($0).png") }
    }

    @Test func aDropAddsToTheCurrentBoxAndShowsAddedWithUndo() async throws {
        let boxRig = try BoxRig()
        let box = boxRig.controller()
        box.start()
        let rig = try TrayRig(box: box)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        let board = TestPasteboard(urls: try files(boxRig, 3))
        let info = FakeDraggingInfo(pasteboard: board.board)
        #expect(rig.tray.draggingEntered(info, display: 1) == .copy)
        #expect(rig.tray.performDrop(info, display: 1))
        await rig.tray.dropTask?.value
        #expect(box.current?.items.count == 3)
        #expect(rig.shown(on: 1).contains(.toast))
        #expect(rig.tray.lastToast?.text == "Added 3" && rig.tray.lastToast?.spoken == "Added 3 items")
        await rig.tray.toastTask?.value
        #expect(rig.lingers == [.seconds(4)])
        withExtendedLifetime((boxRig, board)) {}
    }

    @Test func undoRemovesExactlyTheItemsThatDropAdded() async throws {
        let boxRig = try BoxRig()
        let box = boxRig.controller()
        box.start()
        _ = await box.add([try boxRig.dir.file("kept.png")], newBox: false)
        let rig = try TrayRig(box: box)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        let board = TestPasteboard(urls: try files(boxRig, 3))
        #expect(rig.tray.performDrop(FakeDraggingInfo(pasteboard: board.board), display: 1))
        await rig.tray.dropTask?.value
        #expect(box.current?.items.count == 4)
        rig.tray.undoLastDrop()
        #expect(box.current?.items.map(\.displayName) == ["kept.png"])
        #expect(rig.tray.lastToast == nil)
        withExtendedLifetime((boxRig, board)) {}
    }

    @Test func aRefusedDropShowsTheReasonAndAddsNothing() async throws {
        let rig = try TrayRig(boxItems: 2)
        rig.box.nextAdd = TrayAdded(outcome: AddOutcome(added: 0, failure: IntakeResult.nothingUsable), ids: [])
        rig.tray.proximity(.entered(display: 1), itemCount: 1)
        let info = FakeDraggingInfo(pasteboard: TestPasteboard().board)
        #expect(rig.tray.performDrop(info, display: 1))
        await rig.tray.dropTask?.value
        #expect(rig.box.count == 2)
        #expect(rig.tray.lastToast?.failed == true)
        #expect(rig.tray.lastToast?.text == "Only items stored on this Mac can be added")
        await rig.tray.toastTask?.value
        #expect(rig.lingers == [.milliseconds(1_500)])
    }

    @Test func afterTheToastTheTrayGoesBackToRest() async throws {
        let rig = try TrayRig(boxItems: 2)
        rig.box.nextAdd = TrayAdded(outcome: AddOutcome(added: 1), ids: [UUID()])
        rig.tray.proximity(.entered(display: 1), itemCount: 1)
        _ = rig.tray.performDrop(FakeDraggingInfo(pasteboard: TestPasteboard().board), display: 1)
        await rig.tray.dropTask?.value
        await rig.tray.toastTask?.value
        #expect(rig.hosts.surface(on: 1) == .sensor && rig.tray.lastToast == nil)
        #expect(rig.shown(on: 1).suffix(3) == [.dropTarget, .toast, .sensor])
    }

    @Test func aHeldToastWaitsUntilItIsLetGo() async throws {
        let rig = try TrayRig(boxItems: 2)
        rig.box.nextAdd = TrayAdded(outcome: AddOutcome(added: 1), ids: [UUID()])
        rig.tray.proximity(.entered(display: 1), itemCount: 1)
        rig.tray.held(true, display: 1, now: .zero)
        _ = rig.tray.performDrop(FakeDraggingInfo(pasteboard: TestPasteboard().board), display: 1)
        await rig.tray.dropTask?.value
        #expect(rig.lingers.isEmpty && rig.hosts.surface(on: 1) == .toast)
        rig.tray.held(false, display: 1, now: .zero)
        await rig.tray.toastTask?.value
        #expect(rig.lingers == [.seconds(4)] && rig.hosts.surface(on: 1) == .sensor)
    }

    @Test func dragsOverTheTrayAreTakenOnlyOnItsDropTarget() throws {
        let rig = try TrayRig(boxItems: 2)
        let info = FakeDraggingInfo(pasteboard: TestPasteboard().board)
        #expect(rig.tray.draggingEntered(info, display: 1) == [])
        #expect(!rig.tray.performDrop(info, display: 1))
        rig.tray.proximity(.entered(display: 1), itemCount: 1)
        #expect(rig.tray.draggingUpdated(info, display: 1) == .copy)
        rig.tray.draggingExited(display: 1)
        #expect(rig.tray.dragTypes == BoxDropView.types)
    }

    @Test func theCompactViewListsTheBox() async throws {
        let boxRig = try BoxRig()
        let box = boxRig.controller()
        box.start()
        _ = await box.add(try files(boxRig, 2), newBox: false)
        #expect(box.trayModel.items.map(\.name) == ["tray-0.png", "tray-1.png"])
        let rig = try TrayRig(box: box)
        #expect(rig.hosts.surface(on: 1) == .sensor)
        withExtendedLifetime(boxRig) {}
    }

    @Test func openDropBoxShowsThePanelBelowTheIsland() async throws {
        let boxRig = try BoxRig()
        let box = boxRig.controller()
        box.start()
        _ = await box.add(try files(boxRig, 1), newBox: false)
        let rig = try TrayRig(box: box)
        rig.tray.pressed(.openPanel, display: 1)
        #expect(box.presentation.base == .expanded)
        box.hidePanel()
        withExtendedLifetime(boxRig) {}
    }

    @Test func aDragFromTheStripHoldsTheIslandUntilItEnds() throws {
        let rig = try TrayRig(boxItems: 3)
        rig.hosts.expandRequested(on: 1)
        #expect(rig.hosts.surface(on: 1) == .expanded)
        rig.tray.stripDrag(true, display: 1)
        #expect(rig.tray.heldDisplays.contains(1))
        rig.tray.stripDrag(false, display: 1)
        #expect(rig.hosts.surface(on: 1) == .expanded)
    }
}

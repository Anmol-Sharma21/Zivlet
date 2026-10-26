import AppKit
import Testing
import ZivletActions
import ZivletShelfCore

@testable import ZivletBox

@Suite("Box storage, Empty Box Storage and auto-clear (P2-141, P2-142, OWN-APP-3)")
@MainActor
struct BoxStorageTests {
    /// Adds an owned clipping to the current box (or a new one).
    static func addClipping(_ box: BoxController, _ text: String = "kept words") async {
        let clipping = TestPasteboard(string: text)
        _ = await box.receiveDrop(clipping.board)
        withExtendedLifetime(clipping) {}
    }

    @Test func theOverflowMenuStartsWithTheStorageLine() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        await Self.addClipping(box)
        #expect(box.storageBytes == 10 && box.viewModel.storageLine == "Box storage 10 bytes")
        #expect(BoxCopy.storage(1_200_000_000) == "Box storage 1.2 GB")
        #expect(!box.viewModel.storageWarning)
    }

    @Test func theDotAppearsAtTwoGigabytes() {
        func model(_ bytes: Int64) -> BoxViewModel {
            BoxViewModel(
                items: [], selection: [], presentation: BoxPresentation(), viewMode: .grid, finish: .solid,
                maxHeight: 600, storageBytes: bytes)
        }
        #expect(model(2_000_000_000).storageWarning && !model(1_999_999_999).storageWarning)
    }

    @Test func emptyBoxStorageRemovesOwnedItemsFromEveryBoxAfterTheInlineConfirm() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        await Self.addClipping(box, "one")
        _ = await box.add(try rig.files(1, prefix: "g"), newBox: true)
        await Self.addClipping(box, "two")
        box.showPanel()
        box.press(.emptyStorage)
        #expect(box.presentation.overlay == .confirm(.emptyStorage) && rig.trash.calls.isEmpty)
        box.press(.confirm(true))
        #expect(rig.trash.calls.count == 2)
        #expect(box.library.boxes.map { $0.items.map(\.displayName) } == [["f0.txt"], ["g0.txt"]])
        #expect(rig.results.results == [.done(toast: "Box storage emptied", undo: nil)])
        box.hidePanel()
    }

    @Test func aDragOutThatLandsClearsTheDraggedItemsWhenAsked() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.autoClear = { .afterLeaving }
        box.start()
        _ = await box.add(try rig.files(2), newBox: false)
        box.press(.draggedOut([box.viewModel.items[0].id]))
        #expect(box.library.current?.items.map(\.displayName) == ["f1.txt"])
    }

    @Test func nothingClearsWithThePolicyOff() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(2), newBox: false)
        box.press(.draggedOut(box.viewModel.items.map(\.id)))
        rig.now = rig.now.addingTimeInterval(AutoClearPlan.day * 2)
        box.showPanel()
        #expect(box.library.current?.items.count == 2)
        box.hidePanel()
    }

    @Test func afterADayItemsLeaveAtLaunchAndWhenTheBoxIsShown() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.autoClear = { .after24Hours }
        first.start()
        _ = await first.add(try rig.files(1), newBox: false)
        rig.now = rig.now.addingTimeInterval(AutoClearPlan.day + 1)
        _ = await first.add(try rig.files(1, prefix: "g"), newBox: false)
        first.quit()
        let relaunched = rig.controller()
        relaunched.autoClear = { .after24Hours }
        relaunched.start()
        #expect(relaunched.library.current?.items.map(\.displayName) == ["g0.txt"])
        rig.now = rig.now.addingTimeInterval(AutoClearPlan.day + 1)
        relaunched.showPanel()
        #expect(relaunched.library.current?.items.isEmpty == true)
        relaunched.hidePanel()
    }

    @Test func aFinishedMoveClearsTheMovedItemsWhenAsked() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.autoClear = { .afterLeaving }
        box.start()
        _ = await box.add(try rig.files(2), newBox: false)
        box.press(.select(box.viewModel.items[1].id, extend: false, toggle: false))
        box.press(.moveTo)
        await box.running?.value
        #expect(box.library.current?.items.map(\.displayName) == ["f0.txt"])
    }
}

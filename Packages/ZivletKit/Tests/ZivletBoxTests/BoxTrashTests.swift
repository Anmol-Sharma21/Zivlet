import Foundation
import TestSupport
import Testing
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletShelfCore

@testable import ZivletBox

@Suite("Move to Trash from the box: off the main thread, cancellable, with Undo (G-M5b-8, G-M5b-9)")
@MainActor
struct BoxTrashTests {
    /// A shown box of `items` files whose Trash is a folder of the sandbox.
    static func box(_ rig: BoxRig, items: Int) async throws -> (BoxController, [URL]) {
        rig.trash.folder = try rig.dir.folder("Trash")
        let box = rig.controller()
        box.start()
        let files = try rig.files(items)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        return (box, files)
    }

    /// Undo as the app runs it: the history puts the files back, then the box takes its items back.
    static func undo(_ batch: BatchID, rig: BoxRig, box: BoxController) async -> UndoResult? {
        let result = await rig.undo.undo(batch)
        box.trashUndone(batch, restored: result?.restored ?? [])
        return result
    }

    @Test func aCancelledTrashKeepsTheRestAndUndoBringsBackWhatWent() async throws {
        let rig = try BoxRig()
        let (box, files) = try await Self.box(rig, items: 200)
        let order = box.library.current?.items.map(\.id)
        rig.trash.pauseAt = 50
        box.press(.trash)
        box.press(.confirm(true))
        try await waitUntil { rig.trash.isHeld }
        let probe = Task { @MainActor in true }
        #expect(await probe.value)
        try await waitUntil {
            if case .busy(let verb, _) = box.presentation.overlay { return verb == "Moving 200 items to the Trash" }
            return false
        }
        box.apply(.escape)
        rig.trash.resume()
        await box.running?.value
        let result = try #require(rig.results.results.last)
        #expect(box.library.current?.items.count == 150 && box.presentation.overlay == nil)
        #expect(result.toast == "Moved 50 to the Trash" && result.card?.title == "Stopped. 150 items are still here.")
        let undone = await Self.undo(try #require(result.undo), rig: rig, box: box)
        #expect(undone?.restored.count == 50 && files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(box.library.current?.items.map(\.id) == order)
        box.hidePanel()
    }

    @Test func oneItemGoesWithoutTheOverlayAndCanBeUndone() async throws {
        let rig = try BoxRig()
        let (box, files) = try await Self.box(rig, items: 2)
        box.press(.select(box.viewModel.items[1].id, extend: false, toggle: false))
        box.press(.trash)
        #expect(box.presentation.overlay == nil)
        await box.running?.value
        let result = try #require(rig.results.results.last)
        #expect(result.toast == "Moved 1 to the Trash" && result.card == nil)
        #expect(!FileManager.default.fileExists(atPath: files[1].path))
        _ = await Self.undo(try #require(result.undo), rig: rig, box: box)
        #expect(FileManager.default.fileExists(atPath: files[1].path))
        #expect(box.library.current?.items.map(\.displayName) == ["f0.txt", "f1.txt"])
        box.hidePanel()
    }

    @Test func aRefusedItemIsListedAndTheRestGo() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, items: 3)
        rig.trash.refusing = ["f1.txt"]
        box.press(.trash)
        box.press(.confirm(true))
        await box.running?.value
        let result = try #require(rig.results.results.last)
        #expect(result.toast == "Moved 2 to the Trash")
        #expect(result.card?.lines == ["f1.txt couldn't be moved to the Trash."])
        #expect(box.library.current?.items.map(\.displayName) == ["f1.txt"])
        box.hidePanel()
    }

    @Test func aRefusedItemSaysWhyWhenTheSystemSaid() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, items: 2)
        rig.trash.refusing = ["f0.txt"]
        rig.trash.refusal = .trashRefused(.noPermission)
        box.press(.trash)
        box.press(.confirm(true))
        await box.running?.value
        let result = try #require(rig.results.results.last)
        #expect(result.card?.lines == ["f0.txt couldn't be moved to the Trash: no permission."])
        box.hidePanel()
    }

    @Test func anItemRemovedWhileTrashingIsNotBroughtBack() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, items: 3)
        rig.trash.pauseAt = 2
        box.press(.trash)
        box.press(.confirm(true))
        try await waitUntil { rig.trash.isHeld }
        let last = try #require(box.library.current?.items.last)
        box.remove([last], from: try #require(box.current))
        rig.trash.resume()
        await box.running?.value
        let result = try #require(rig.results.results.last)
        #expect(result.toast == "Moved 3 to the Trash" && box.library.current?.items.isEmpty == true)
        _ = await Self.undo(try #require(result.undo), rig: rig, box: box)
        #expect(box.library.current?.items.map(\.displayName) == ["f0.txt", "f1.txt"])
        box.hidePanel()
    }

    @Test func aStopAfterOnlyARefusalSaysNothingWent() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, items: 2)
        rig.trash.pauseAt = 1
        rig.trash.refusing = ["f0.txt"]
        box.press(.trash)
        box.press(.confirm(true))
        try await waitUntil { rig.trash.isHeld }
        box.apply(.escape)
        rig.trash.resume()
        await box.running?.value
        #expect(rig.results.results.last?.card?.title == "Nothing was moved to the Trash.")
        #expect(box.library.current?.items.count == 2)
        box.hidePanel()
    }

    @Test func stoppedTitlesCountWhatIsLeft() {
        #expect(BoxCopy.stillHere(1) == "Stopped. 1 item is still here.")
        #expect(BoxCopy.stillHere(150) == "Stopped. 150 items are still here.")
    }
}

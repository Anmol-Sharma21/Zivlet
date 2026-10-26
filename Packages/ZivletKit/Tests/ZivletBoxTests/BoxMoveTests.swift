import Foundation
import Testing
import ZivletActions
import ZivletRuntime
import ZivletShelfCore

@testable import ZivletBox

@Suite("Move to… from the box: one undo, references follow (P2-142)")
@MainActor
struct BoxMoveTests {
    @Test func theSelectionMovesWithOneUndoBatchAndItsItemsFollow() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(3)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        let ids = box.viewModel.items.map(\.id)
        box.press(.select(ids[0], extend: false, toggle: false))
        box.press(.select(ids[2], extend: false, toggle: true))
        box.press(.moveTo)
        await box.running?.value
        #expect(rig.results.results.map(\.toast) == ["Moved 2 items"] && rig.results.results.first?.undo != nil)
        #expect(await rig.undo.recent().count == 1)
        let destination = rig.destination.standardizedFileURL.path
        let paths = box.library.current?.items.map(\.lastKnownPath)
        #expect(paths == [destination + "/f0.txt", files[1].standardizedFileURL.path, destination + "/f2.txt"])
        #expect(rig.saved()?.current?.items.map(\.lastKnownPath) == paths)
        #expect(box.viewModel.items[0].url?.path == destination + "/f0.txt")
        box.hidePanel()
    }

    @Test func aCancelledFolderChoiceChangesNothing() async throws {
        let rig = try BoxRig()
        rig.folders.answer = nil
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add(files, newBox: false)
        let before = box.library
        box.press(.moveTo)
        await box.running?.value
        #expect(box.library == before && rig.folders.asked == 1 && rig.results.results == [.cancelled])
        #expect(FileManager.default.fileExists(atPath: files[0].path))
    }

    @Test func itemsThatCannotMoveStayAndAreListed() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add(files, newBox: false)
        rig.bookmarks.resolutions[files[1].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: nil, storedVolumeName: nil)
        box.showPanel()
        box.press(.moveTo)
        await box.running?.value
        let card = ActionCard(title: "1 item was left out.", lines: ["f1.txt is missing."])
        #expect(rig.results.results.first?.card == card && rig.results.results.first?.toast == "Moved 1 item")
        #expect(box.library.current?.items[1].lastKnownPath == files[1].standardizedFileURL.path)
        box.hidePanel()
    }
}

import AppKit
import Testing
import ZivletActions
import ZivletShelfCore

@testable import ZivletBox

@Suite("AirDrop, Copy and Copy Paths from the box (P2-142)")
@MainActor
struct BoxActionsTests {
    @Test func copyPutsTwoHundredItemsOnTheClipboard() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(200), newBox: false)
        box.showPanel()
        box.press(.copy)
        let copied = rig.board.board.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(copied?.count == 200)
        #expect(rig.results.results == [.done(toast: "Copied 200 items", undo: nil)])
        box.hidePanel()
    }

    @Test func copyPathsWritesOneLinePerItemAndOptionQuotesThem() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        box.press(.copyPaths)
        #expect(
            rig.board.board.string(forType: .string) == files.map(\.standardizedFileURL.path).joined(separator: "\n"))
        rig.optionHeld = true
        box.press(.copyPaths)
        #expect(rig.board.board.string(forType: .string)?.hasPrefix("'") == true)
        #expect(rig.results.results.map(\.toast) == ["Copied 2 paths", "Copied 2 paths"])
        box.hidePanel()
    }

    @Test func theCopyPathsKeyIsNeverQuoted() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(1)
        _ = await box.add(files, newBox: false)
        rig.optionHeld = true
        #expect(box.handleKey(BoxKeyStroke(chars: "c", command: true, option: true)))
        #expect(rig.board.board.string(forType: .string) == files[0].standardizedFileURL.path)
    }

    @Test func unavailableItemsBecomeCardLines() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(3)
        _ = await box.add(files, newBox: false)
        rig.bookmarks.resolutions[files[2].standardizedFileURL.path] = .resolved(
            path: "/Users/u/.Trash/f2.txt", stale: true)
        box.showPanel()
        box.press(.copy)
        let card = ActionCard(title: "1 item was left out.", lines: ["f2.txt is in the Trash."])
        #expect(rig.results.results == [.partial(toast: "Copied 2 items", card: card, undo: nil)])
        box.hidePanel()
    }

    @Test func airDropWaitsOneTurnThenSendsTheTargets() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add(files, newBox: false)
        box.press(.airDrop)
        await box.running?.value
        #expect(rig.turns == 1 && rig.sharing.performed == [files.map(\.standardizedFileURL)])
        #expect(rig.results.results == [.done(toast: "Sent with AirDrop", undo: nil)])
    }

    @Test func airDropUnavailableShowsTheExistingCard() async throws {
        let rig = try BoxRig()
        rig.sharing = FakeBoxSharing(available: false)
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        box.press(.airDrop)
        await box.running?.value
        #expect(rig.results.results == [.failed(ActionCard(title: ActionError.airDropUnavailable.userMessage))])
    }

    @Test func nothingUsableIsACardWithoutRunningTheAction() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(1)
        _ = await box.add(files, newBox: false)
        rig.bookmarks.resolutions[files[0].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: "/Volumes/Backup", storedVolumeName: "Backup")
        rig.mounted = false
        box.showPanel()
        box.press(.airDrop)
        await box.running?.value
        #expect(rig.sharing.performed.isEmpty)
        let card = ActionCard(
            title: "Nothing here can be sent.", lines: ["f0.txt is on Backup, which isn't connected."])
        #expect(rig.results.results == [.failed(card)])
        box.hidePanel()
    }

    @Test func anEmptyBoxDoesNothingAndSaysNothing() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        _ = box.handleKey(BoxKeyStroke(chars: "n", command: true))
        for press in [BoxPress.copy, .copyPaths, .airDrop, .share, .moveTo, .copyTo, .trash] { box.press(press) }
        await box.running?.value
        #expect(rig.results.results.isEmpty && rig.picker.shown.isEmpty && rig.folders.asked == 0)
    }
}

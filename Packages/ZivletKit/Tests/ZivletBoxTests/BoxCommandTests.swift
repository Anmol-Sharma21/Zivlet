import AppKit
import TestSupport
import Testing
import ZivletActions
import ZivletCore
import ZivletShelfCore

@testable import ZivletBox

@Suite("Remove, Move to Trash, Clear, Locate… and Remove missing (P2-142, D-M5b-12, D-M5b-21)")
@MainActor
struct BoxCommandTests {
    /// A box of `files` plain references and one owned clipping, shown expanded.
    static func box(_ rig: BoxRig, files: Int, owned: Bool = false) async throws -> (BoxController, [URL]) {
        let box = rig.controller()
        box.start()
        let urls = try rig.files(files)
        _ = await box.add(urls, newBox: false)
        if owned {
            let clipping = TestPasteboard(string: "kept words")
            _ = await box.receiveDrop(clipping.board)
            withExtendedLifetime(clipping) {}
        }
        box.showPanel()
        return (box, urls)
    }

    @Test func removeDropsTheSelectedReferencesAndTrashesAnOwnedCopy() async throws {
        let rig = try BoxRig()
        let (box, files) = try await Self.box(rig, files: 2, owned: true)
        let ids = box.viewModel.items.map(\.id)
        box.press(.select(ids[0], extend: false, toggle: false))
        box.press(.select(ids[2], extend: false, toggle: true))
        #expect(box.handleKey(BoxKeyStroke(special: .delete)))
        #expect(box.library.current?.items.map(\.id) == [ids[1]] && rig.saved()?.current?.items.count == 1)
        #expect(rig.trash.calls.count == 1 && rig.trash.calls.first?.pathExtension == "txt")
        #expect(rig.trash.calls.first != files[0] && FileManager.default.fileExists(atPath: files[0].path))
        #expect(rig.results.results.isEmpty)
        box.hidePanel()
    }

    @Test func anOwnedCopyTheTrashRefusesKeepsItsItem() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, files: 0, owned: true)
        let item = try #require(box.library.current?.items.first)
        rig.trash.refusing = [item.displayName]
        box.press(.select(item.id, extend: false, toggle: false))
        box.press(.remove)
        #expect(box.library.current?.items.map(\.id) == [item.id])
        let line = "\(item.displayName) stayed: its kept copy couldn't be moved to the Trash."
        #expect(rig.results.results == [.failed(ActionCard(title: "Some items stayed in the box.", lines: [line]))])
        box.hidePanel()
    }

    @Test func removeWithNothingSelectedAsksToClearTheBox() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, files: 2)
        box.press(.remove)
        #expect(box.presentation.overlay == .confirm(.clear) && box.library.current?.items.count == 2)
        box.hidePanel()
    }

    @Test func trashOfOneItemRunsAtOnce() async throws {
        let rig = try BoxRig()
        let (box, files) = try await Self.box(rig, files: 2)
        box.press(.select(box.viewModel.items[1].id, extend: false, toggle: false))
        #expect(box.handleKey(BoxKeyStroke(special: .delete, command: true)))
        #expect(box.presentation.overlay == nil)
        await box.running?.value
        #expect(box.presentation.overlay == nil && rig.trash.calls == [files[1].standardizedFileURL])
        #expect(box.library.current?.items.map(\.displayName) == ["f0.txt"])
        #expect(rig.results.results.map(\.toast) == ["Moved 1 to the Trash"] && rig.results.results[0].undo != nil)
        box.hidePanel()
    }

    @Test func trashOfMoreThanOneAsksFirstInline() async throws {
        let rig = try BoxRig()
        let (box, files) = try await Self.box(rig, files: 2)
        box.press(.trash)
        #expect(box.presentation.overlay == .confirm(.trash(count: 2)) && rig.trash.calls.isEmpty)
        box.press(.confirm(true))
        await box.running?.value
        #expect(rig.trash.calls == files.map(\.standardizedFileURL) && box.library.current?.items.isEmpty == true)
        #expect(rig.results.results.map(\.toast) == ["Moved 2 to the Trash"] && rig.results.results[0].undo != nil)
        box.hidePanel()
    }

    @Test func escapeAnswersNo() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, files: 2)
        box.press(.trash)
        #expect(box.handleKey(BoxKeyStroke(special: .escape)))
        #expect(box.presentation.overlay == nil && box.presentation.base == .expanded)
        #expect(rig.trash.calls.isEmpty && box.library.current?.items.count == 2)
        box.hidePanel()
    }

    @Test func whatTheTrashRefusesStaysAndIsListed() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, files: 1)
        rig.trash.refusing = ["f0.txt"]
        box.press(.trash)
        await box.running?.value
        let card = ActionCard(
            title: "Nothing was moved to the Trash.", lines: ["f0.txt couldn't be moved to the Trash."])
        #expect(rig.results.results == [.failed(card)] && box.library.current?.items.count == 1)
        box.hidePanel()
    }

    @Test func clearCanBeUndoneForTenSeconds() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, files: 2, owned: true)
        box.press(.clear)
        box.press(.confirm(true))
        #expect(box.library.current?.items.isEmpty == true && rig.trash.calls.isEmpty)
        #expect(rig.results.results.last?.linger == .seconds(10) && rig.results.results.last?.toast == "Cleared")
        let batch = try #require(rig.results.results.last?.undo)
        #expect(box.undoClear(batch))
        #expect(box.library.current?.items.count == 3 && rig.saved()?.current?.items.count == 3)
        await box.clearing?.value
        #expect(rig.trash.calls.isEmpty && !box.undoClear(batch) && rig.slept == [.seconds(10)])
        box.hidePanel()
    }

    @Test func afterTenSecondsTheOwnedCopiesAreTrashed() async throws {
        let rig = try BoxRig()
        rig.sleepHolds = false
        let (box, _) = try await Self.box(rig, files: 1, owned: true)
        box.press(.clear)
        box.press(.confirm(true))
        let batch = try #require(rig.results.results.last?.undo)
        await box.clearing?.value
        #expect(rig.trash.calls.count == 1 && !box.undoClear(batch))
        #expect(box.library.current?.items.isEmpty == true)
        box.hidePanel()
    }

    @Test func quittingDuringTheUndoWindowTrashesTheOwnedCopies() async throws {
        let rig = try BoxRig()
        let (box, _) = try await Self.box(rig, files: 1, owned: true)
        box.press(.clear)
        box.press(.confirm(true))
        box.quit()
        #expect(rig.trash.calls.count == 1)
        box.hidePanel()
    }

    @Test func locateGivesAMissingItemItsNewPlace() async throws {
        let rig = try BoxRig()
        let found = try rig.dir.file("elsewhere/f0.txt")
        let files = try rig.files(1)
        rig.bookmarks.resolutions[files[0].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: nil, storedVolumeName: nil)
        let box = rig.controller()
        box.start()
        _ = await box.add(files, newBox: false)
        box.showPanel()
        box.press(.select(box.viewModel.items[0].id, extend: false, toggle: false))
        #expect(box.viewModel.canLocate)
        rig.locator.answer = found
        box.press(.locate)
        await box.running?.value
        #expect(rig.locator.asked == ["f0.txt"] && box.viewModel.items[0].isAvailable)
        #expect(rig.saved()?.current?.items.first?.lastKnownPath == found.standardizedFileURL.path)
        box.hidePanel()
    }

    @Test func aCancelledLocateChangesNothing() async throws {
        let rig = try BoxRig()
        let files = try rig.files(1)
        rig.bookmarks.resolutions[files[0].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: nil, storedVolumeName: nil)
        let box = rig.controller()
        box.start()
        _ = await box.add(files, newBox: false)
        box.showPanel()
        let before = box.library
        box.press(.select(box.viewModel.items[0].id, extend: false, toggle: false))
        box.press(.locate)
        await box.running?.value
        #expect(box.library == before && !box.viewModel.items[0].isAvailable)
        box.hidePanel()
    }

    @Test func removeMissingKeepsItemsOnAVolumeThatIsNotConnected() async throws {
        let rig = try BoxRig()
        let files = try rig.files(4)
        rig.bookmarks.resolutions[files[1].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: nil, storedVolumeName: nil)
        rig.bookmarks.resolutions[files[2].standardizedFileURL.path] = .resolved(
            path: "/Users/u/.Trash/f2.txt", stale: true)
        rig.bookmarks.resolutions[files[3].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: "/Volumes/Backup", storedVolumeName: "Backup")
        rig.mounted = false
        let box = rig.controller()
        box.start()
        _ = await box.add(files, newBox: false)
        box.showPanel()
        box.press(.removeMissing)
        #expect(box.library.current?.items.map(\.displayName) == ["f0.txt", "f3.txt"] && rig.trash.calls.isEmpty)
        box.hidePanel()
    }

    @Test func zivletBoxNeverRaisesAnAlert() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/ZivletBox")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let swift = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!swift.isEmpty)
        for file in swift { #expect(try !String(contentsOf: file, encoding: .utf8).contains("NSAlert")) }
    }
}

@Suite("Locate… panel set-up")
@MainActor
struct LocatePanelTests {
    @Test func thePanelFindsOneItemWhereItWasLastSeen() throws {
        let rig = try BoxRig()
        let panel = NSOpenPanel()
        SystemFileLocator.configure(panel, name: "photo.heic", folder: rig.dir.url, above: .floating)
        #expect(panel.canChooseFiles && panel.canChooseDirectories && !panel.allowsMultipleSelection)
        #expect(panel.prompt == "Locate" && panel.message == "Find “photo.heic”.")
        #expect(panel.directoryURL?.standardizedFileURL == rig.dir.url.standardizedFileURL)
        #expect(panel.level.rawValue > NSWindow.Level.floating.rawValue)
    }
}

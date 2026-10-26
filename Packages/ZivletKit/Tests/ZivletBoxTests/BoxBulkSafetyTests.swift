import AppKit
import TestSupport
import Testing
import ZivletActions
import ZivletShelfCore

@testable import ZivletBox

/// A folder chooser that waits until the test answers, so a second press can arrive while the first is open.
final class HeldFolders: FolderChoosing {
    private var waiting: CheckedContinuation<URL?, Never>?
    private(set) var asked = 0

    func chooseFolder(for items: [MoveItem]) async -> URL? {
        asked += 1
        return await withCheckedContinuation { waiting = $0 }
    }

    func answer(_ url: URL?) {
        waiting?.resume(returning: url)
        waiting = nil
    }
}

/// The review's bulk-action findings: targets come from the bookmarks at the time of the action, one action runs
/// at a time, items whose move could not be followed are named, and Share names what it left out.
@Suite("Bulk actions act on the right files, one at a time (P2-142)")
@MainActor
struct BoxBulkSafetyTests {
    static func box(_ rig: BoxRig, files: Int) async throws -> (BoxController, [URL]) {
        let box = rig.controller()
        box.start()
        let urls = try rig.files(files)
        _ = await box.add(urls, newBox: false)
        return (box, urls)
    }

    @Test func trashActsOnWhereTheBookmarkSaysTheFileIsNow() async throws {
        let rig = try BoxRig()
        let (box, urls) = try await Self.box(rig, files: 1)
        box.showPanel()
        let renamed = rig.dir.url.appending(path: "files/renamed.txt").path
        rig.bookmarks.resolutions[urls[0].standardizedFileURL.path] = .resolved(path: renamed, stale: false)
        box.press(.trash)
        await box.running?.value
        #expect(rig.trash.calls.map(\.path) == [renamed])
        box.hidePanel()
    }

    @Test func copyFromTheTrayBeforeAnyShowLeavesOutAFileThatIsGone() async throws {
        let rig = try BoxRig()
        let (box, urls) = try await Self.box(rig, files: 2)
        let restarted = rig.controller()
        restarted.start()
        rig.bookmarks.resolutions[urls[0].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: "/", storedVolumeName: "Disk")
        restarted.press(.copy)
        #expect(rig.results.results.last?.card?.lines == ["f0.txt is missing."])
        withExtendedLifetime(box) {}
    }

    @Test func aSecondMoveWhileTheFirstChooserIsOpenDoesNothing() async throws {
        let rig = try BoxRig()
        let held = HeldFolders()
        rig.chooser = held
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        box.press(.moveTo)
        await settle()
        let first = box.running
        box.press(.moveTo)
        box.press(.copyTo)
        await settle()
        #expect(held.asked == 1 && box.running == first)
        held.answer(nil)
        await first?.value
        #expect(box.running == nil)
    }

    @Test func aMovedItemWhoseNewBookmarkFailsIsNamedAndNotCleared() async throws {
        let rig = try BoxRig()
        rig.maker = FailingAtBookmarks(failing: rig.destination.standardizedFileURL.path + "/f0.txt")
        let box = rig.controller()
        box.autoClear = { .afterLeaving }
        box.start()
        _ = await box.add(try rig.files(2), newBox: false)
        box.press(.moveTo)
        await box.running?.value
        #expect(rig.results.results.last?.card?.lines == ["f0.txt moved, but the box lost track of it."])
        #expect(box.current?.items.map(\.displayName) == ["f0.txt"])
    }

    @Test func shareNamesWhatItLeftOut() async throws {
        let rig = try BoxRig()
        let (box, urls) = try await Self.box(rig, files: 2)
        rig.bookmarks.resolutions[urls[1].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: "/", storedVolumeName: "Disk")
        box.press(.share)
        #expect(rig.picker.shown.first?.urls.map(\.lastPathComponent) == ["f0.txt"])
        #expect(rig.results.results.last?.card?.lines == ["f1.txt is missing."])
        rig.picker.onFailure()
        #expect(rig.results.results.last?.card?.title == "Sharing didn't finish.")
    }

    @Test func quickLookOfOneItemFromVoiceOver() async throws {
        let rig = try BoxRig()
        let (box, urls) = try await Self.box(rig, files: 2)
        let id = try #require(box.current?.items.last?.id)
        box.press(.select(id, extend: false, toggle: false))
        box.press(.quickLook)
        #expect(rig.quickLook.previews.last?.map(\.lastPathComponent) == [urls[1].lastPathComponent])
        box.hidePanel()
    }
}

/// Bookmarks as the fake makes them, failing at one path.
struct FailingAtBookmarks: BookmarkMaking {
    let failing: String

    func bookmark(for url: URL) throws(ShelfError) -> Data {
        guard url.standardizedFileURL.path != failing else { throw .bookmarkFailed }
        return Data(url.path.utf8)
    }

    func identity(of url: URL) -> FileIdentity? { nil }
    func size(of url: URL) -> Int64? { 1_000 }
}

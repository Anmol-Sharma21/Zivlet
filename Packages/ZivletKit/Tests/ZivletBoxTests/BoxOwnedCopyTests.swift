import AppKit
import TestSupport
import Testing
import ZivletActions
import ZivletShelfCore

@testable import ZivletBox

/// The review's owned-copy findings: the box trashes only its own copies, writes them into the folder of the box
/// that keeps them, never leaves one behind that no item points at, and says what a load lost.
@Suite("Owned copies stay the box's own (P2-141)")
@MainActor
struct BoxOwnedCopyTests {
    static func clip(_ box: BoxController, _ text: String = "kept words") async -> AddOutcome {
        let board = TestPasteboard(string: text)
        let outcome = await box.receiveDrop(board.board)
        withExtendedLifetime(board) {}
        return outcome
    }

    static func ownedPath(_ item: ShelfItem?) -> String? {
        guard case .owned(let relative) = item?.ownership else { return nil }
        return relative
    }

    @Test func aClippingMovedOutOfTheBoxIsAReferenceAndNeverTrashesTheNextClipping() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await Self.clip(box, "first")
        let first = try #require(box.current?.items.first)
        box.press(.moveTo)
        await box.running?.value
        let moved = try #require(box.current?.items.first)
        #expect(moved.ownership == .reference && moved.lastKnownPath.hasPrefix(rig.destination.path))
        _ = await Self.clip(box, "second")
        let second = try #require(box.current?.items.last)
        #expect(Self.ownedPath(second) == Self.ownedPath(first))
        box.press(.select(first.id, extend: false, toggle: false))
        box.press(.remove)
        #expect(rig.trash.calls.isEmpty)
        #expect(box.current?.items.map(\.id) == [second.id])
    }

    @Test func aCopyMovedAwayOnDiskIsNotTheFileAtItsOldPath() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await Self.clip(box, "first")
        let first = try #require(box.current?.items.first)
        let elsewhere = rig.dir.url.appending(path: "Clipping moved.txt").path
        rig.bookmarks.resolutions[first.lastKnownPath] = .resolved(path: elsewhere, stale: false)
        box.showPanel()
        box.press(.select(first.id, extend: false, toggle: false))
        box.press(.remove)
        #expect(rig.trash.calls.isEmpty && box.current?.items.isEmpty == true)
        box.hidePanel()
    }

    @Test func theFirstDropEverKeepsItsCopyInTheNewBoxsFolder() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await Self.clip(box)
        let id = try #require(box.current?.id)
        #expect(Self.ownedPath(box.current?.items.first) == "\(id.uuidString)/Clipping.txt")
        let folders = try FileManager.default.contentsOfDirectory(atPath: rig.storage.root.path)
        #expect(folders == [id.uuidString])
    }

    @Test func aFullBoxSaysSoAndTrashesTheCopyItCouldNotKeep() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let items = try (0..<ShelfLibrary.maxItemsPerBox).map { index in
            try ShelfItem(
                bookmark: Data("/x/\(index)".utf8), lastKnownPath: "/x/\(index)", displayName: "\(index)",
                byteCount: 1, addedAt: rig.now)
        }
        box.library = try ShelfLibrary().adding(items, to: .current, now: rig.now).0
        let outcome = await Self.clip(box)
        #expect(outcome.added == 0 && outcome.overCap == ["Clipping.txt"] && outcome.duplicates.isEmpty)
        #expect(outcome.actionResult == .failed(ActionCard(title: "The box is full.")))
        #expect(rig.trash.calls.map(\.lastPathComponent) == ["Clipping.txt"])
    }

    @Test func aCopyNoItemPointsAtIsSweptAtACleanLaunch() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.start()
        _ = await Self.clip(first)
        first.quit()
        let stray = try rig.storage.reserve(name: "left behind.txt", in: try #require(first.current?.id))
        try Data("x".utf8).write(to: stray)
        let again = rig.controller()
        again.start()
        #expect(rig.trash.calls.map(\.lastPathComponent) == ["left behind.txt"])
    }

    @Test func aDamagedFileIsToldAndSweepsNothing() async throws {
        let rig = try BoxRig()
        var errors: [String] = []
        try Data("{not json".utf8).write(to: rig.store.file)
        let stray = try rig.storage.reserve(name: "maybe someone's.txt", in: UUID())
        try Data("x".utf8).write(to: stray)
        let box = rig.controller()
        box.onError = { errors.append($0) }
        box.start()
        #expect(errors == [BoxLoad.damaged.notice] && rig.trash.calls.isEmpty)
    }

    @Test func emptyBoxStorageAlsoSweepsUnreferencedCopies() async throws {
        let rig = try BoxRig()
        rig.trash.removes = true
        let box = rig.controller()
        box.start()
        _ = await Self.clip(box)
        let stray = try rig.storage.reserve(name: "orphan.txt", in: try #require(box.current?.id))
        try Data("x".utf8).write(to: stray)
        box.emptyStorage()
        #expect(Set(rig.trash.calls.map(\.lastPathComponent)) == ["Clipping.txt", "orphan.txt"])
    }

    @Test func aCopyTheTrashRefusesAfterClearComesBack() async throws {
        let rig = try BoxRig()
        rig.trash.refusing = ["Clipping.txt"]
        let box = rig.controller()
        box.start()
        _ = await Self.clip(box)
        box.showPanel()
        box.press(.clear)
        box.press(.confirm(true))
        #expect(box.current?.items.isEmpty == true)
        box.quit()
        #expect(box.current?.items.map(\.displayName) == ["Clipping.txt"])
        #expect(rig.results.results.last?.card?.title == "Some items stayed in the box.")
        box.hidePanel()
    }

    @Test func anUnchangedLibraryIsNotWrittenAgain() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        let stamp = { try FileManager.default.attributesOfItem(atPath: rig.store.file.path)[.systemFileNumber] as? Int }
        let written = try stamp()
        box.quit()
        #expect(try stamp() == written)
    }

    @Test func aSaveThatKeepsFailingIsToldOnce() async throws {
        let rig = try BoxRig()
        var errors: [String] = []
        let box = rig.controller()
        box.onError = { errors.append($0) }
        box.start()
        try FileManager.default.createDirectory(at: rig.store.file, withIntermediateDirectories: true)
        _ = await box.add(try rig.files(1), newBox: false)
        _ = await box.add(try rig.files(1, prefix: "g"), newBox: false)
        #expect(errors == [BoxStoreError.writeFailed.userMessage])
    }
}

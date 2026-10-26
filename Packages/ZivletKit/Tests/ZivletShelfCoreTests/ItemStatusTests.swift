import Foundation
import Testing

@testable import ZivletShelfCore

@Suite("Item status from a bookmark (D-M5b-3)")
struct ItemStatusTests {
    @Test func aResolvedPathOutsideTheTrashIsPresent() {
        let r = Resolution.resolved(path: "/Users/u/Desktop/a.txt", stale: false)
        #expect(ItemStatus.from(r, isMounted: { _ in true }) == .present(path: "/Users/u/Desktop/a.txt"))
    }

    @Test(arguments: ["/Users/u/.Trash/a.txt", "/Volumes/Backup/.Trashes/501/a.txt"])
    func aResolvedPathInTheTrashIsInTheTrash(_ path: String) {
        let r = Resolution.resolved(path: path, stale: true)
        #expect(ItemStatus.from(r, isMounted: { _ in true }) == .inTrash(path: path))
    }

    @Test func aNameThatOnlyContainsTrashIsNotTheTrash() {
        let r = Resolution.resolved(path: "/Users/u/.Trash-notes/a.txt", stale: false)
        #expect(ItemStatus.from(r, isMounted: { _ in true }) == .present(path: "/Users/u/.Trash-notes/a.txt"))
    }

    @Test func aMissingFileOnAnUnmountedVolumeIsOffline() {
        let r = Resolution.failed(code: 4, storedVolumePath: "/Volumes/Backup", storedVolumeName: "Backup")
        #expect(ItemStatus.from(r, isMounted: { _ in false }) == .volumeOffline(name: "Backup"))
    }

    @Test func anOfflineVolumeWithoutAStoredNameIsNamedByItsFolder() {
        let r = Resolution.failed(code: 4, storedVolumePath: "/Volumes/Backup", storedVolumeName: nil)
        #expect(ItemStatus.from(r, isMounted: { _ in false }) == .volumeOffline(name: "Backup"))
    }

    @Test func aMissingFileOnAMountedVolumeIsMissing() {
        let r = Resolution.failed(code: 4, storedVolumePath: "/", storedVolumeName: "Macintosh HD")
        #expect(ItemStatus.from(r, isMounted: { _ in true }) == .missing)
    }

    @Test func anyOtherFailureIsMissing() {
        let other = Resolution.failed(code: 259, storedVolumePath: "/Volumes/Backup", storedVolumeName: "Backup")
        let noVolume = Resolution.failed(code: 4, storedVolumePath: nil, storedVolumeName: nil)
        #expect(ItemStatus.from(other, isMounted: { _ in false }) == .missing)
        #expect(ItemStatus.from(noVolume, isMounted: { _ in false }) == .missing)
    }

    @Test func onlyAPresentItemCanBeUsed() {
        #expect(ItemStatus.present(path: "/a").isAvailable)
        #expect(!ItemStatus.inTrash(path: "/a").isAvailable && !ItemStatus.missing.isAvailable)
        #expect(!ItemStatus.volumeOffline(name: "B").isAvailable)
    }
}

@Suite("Resolving a box (D-M5b-3): stale items are refreshed, nothing else changes")
struct ShelfResolveTests {
    @Test func aStaleItemGetsAFreshBookmarkAndPath() throws {
        let item = try ShelfFixtures.item("a.txt", path: "/old/a.txt")
        let fakes = FakeBookmarks(resolutions: [item.bookmark: .resolved(path: "/new/b.txt", stale: true)])
        let resolved = try ShelfFixtures.shelf(item).resolving(with: fakes, maker: fakes, isMounted: { _ in true })
        let fresh = try #require(resolved.shelf.items.first)
        #expect(resolved.statuses[item.id] == .present(path: "/new/b.txt"))
        #expect(fresh.lastKnownPath == "/new/b.txt" && fresh.bookmark == Data("/new/b.txt".utf8) && fresh.id == item.id)
        #expect(resolved.refreshFailed.isEmpty)
    }

    @Test func aFreshItemIsLeftAsItIs() throws {
        let item = try ShelfFixtures.item("a.txt", path: "/x/a.txt")
        let fakes = FakeBookmarks(resolutions: [item.bookmark: .resolved(path: "/x/a.txt", stale: false)])
        let shelf = try ShelfFixtures.shelf(item)
        #expect(shelf.resolving(with: fakes, maker: fakes, isMounted: { _ in true }).shelf == shelf)
    }

    @Test func aRefreshThatFailsKeepsTheOldItemAndSaysSo() throws {
        let item = try ShelfFixtures.item("a.txt", path: "/old/a.txt")
        var fakes = FakeBookmarks(resolutions: [item.bookmark: .resolved(path: "/new/a.txt", stale: true)])
        fakes.failing = ["/new/a.txt"]
        let shelf = try ShelfFixtures.shelf(item)
        let resolved = shelf.resolving(with: fakes, maker: fakes, isMounted: { _ in true })
        #expect(resolved.shelf == shelf && resolved.refreshFailed == [item.id])
        #expect(resolved.statuses[item.id] == .present(path: "/new/a.txt"))
    }

    @Test func anItemInTheTrashIsNotRefreshed() throws {
        let item = try ShelfFixtures.item("a.txt", path: "/x/a.txt")
        let fakes = FakeBookmarks(resolutions: [item.bookmark: .resolved(path: "/u/.Trash/a.txt", stale: true)])
        let shelf = try ShelfFixtures.shelf(item)
        let resolved = shelf.resolving(with: fakes, maker: fakes, isMounted: { _ in true })
        #expect(resolved.shelf == shelf && resolved.statuses[item.id] == .inTrash(path: "/u/.Trash/a.txt"))
        #expect(resolved.missingCount == 1)
    }
}

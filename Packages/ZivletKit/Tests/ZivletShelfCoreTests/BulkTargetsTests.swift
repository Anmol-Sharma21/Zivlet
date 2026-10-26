import Foundation
import Testing

@testable import ZivletShelfCore

@Suite("Bulk targets (P2-142: selection, or all; per-item failures)")
struct BulkTargetsTests {
    @Test func noSelectionMeansEveryPresentItem() throws {
        let (shelf, statuses) = try ShelfFixtures.box(present: 3, missing: 1)
        let targets = BulkTargets.resolve(selection: [], in: shelf, statuses: statuses)
        #expect(targets.urls.map(\.lastPathComponent) == ["a.txt", "b.txt", "c.txt"])
        #expect(targets.failures == ["d.txt is missing."])
        #expect(targets.ids == shelf.items.prefix(3).map(\.id))
    }

    @Test func aSelectionKeepsTheBoxOrderNotTheClickOrder() throws {
        let (shelf, statuses) = try ShelfFixtures.box(present: 4, missing: 0)
        let picked: Set<UUID> = [shelf.items[3].id, shelf.items[1].id]
        let targets = BulkTargets.resolve(selection: picked, in: shelf, statuses: statuses)
        #expect(targets.urls.map(\.lastPathComponent) == ["b.txt", "d.txt"])
        #expect(targets.failures.isEmpty && !targets.isEmpty)
    }

    @Test func eachUnavailableStatusIsNamedInZivletsWords() throws {
        let photo = try ShelfFixtures.item("photo.heic")
        let trashed = try ShelfFixtures.item("old.heic")
        let movie = try ShelfFixtures.item("a.mov")
        let shelf = try ShelfFixtures.shelf(photo, trashed, movie)
        let statuses: [UUID: ItemStatus] = [
            photo.id: .missing, trashed.id: .inTrash(path: "/Users/u/.Trash/old.heic"),
            movie.id: .volumeOffline(name: "Backup"),
        ]
        let targets = BulkTargets.resolve(selection: [], in: shelf, statuses: statuses)
        #expect(targets.isEmpty && targets.urls.isEmpty && targets.ids.isEmpty)
        #expect(
            targets.failures == [
                "photo.heic is missing.", "old.heic is in the Trash.", "a.mov is on Backup, which isn't connected.",
            ])
        #expect(BulkTargets.failure("photo.heic", .present(path: "/x/photo.heic")) == nil)
    }

    @Test func aPresentItemUsesItsResolvedPath() throws {
        let item = try ShelfFixtures.item("a.txt")
        let shelf = try ShelfFixtures.shelf(item)
        let targets = BulkTargets.resolve(
            selection: [], in: shelf, statuses: [item.id: .present(path: "/Users/u/Moved/a.txt")])
        #expect(targets.urls == [URL(filePath: "/Users/u/Moved/a.txt")])
    }

    @Test func anUnresolvedItemUsesItsLastKnownPath() throws {
        let item = try ShelfFixtures.item("a.txt", path: "/Users/u/a.txt")
        let targets = BulkTargets.resolve(selection: [], in: try ShelfFixtures.shelf(item), statuses: [:])
        #expect(targets.urls == [URL(filePath: "/Users/u/a.txt")] && targets.ids == [item.id])
    }

    @Test func idsTheBoxDoesNotHoldAreIgnored() throws {
        let (shelf, statuses) = try ShelfFixtures.box(present: 2, missing: 0)
        let targets = BulkTargets.resolve(selection: [UUID()], in: shelf, statuses: statuses)
        #expect(targets.isEmpty && targets.failures.isEmpty)
    }
}

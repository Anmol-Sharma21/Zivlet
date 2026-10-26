import Foundation
import Testing

@testable import ZivletShelfCore

/// The review's ownership findings: an owned copy that leaves the box's storage is the person's file from then on, a
/// relocated item carries the new file's identity, owned paths name one file in one box's folder, and one item id
/// never appears twice in a box.
@Suite("Owned copies, identities and item ids stay true (P2-141)")
struct ShelfOwnershipTests {
    static let box = UUID(uuidString: "6F1E2B9C-0000-4000-8000-0000000000B0")!
    static let storage = OwnedStorage(root: URL(filePath: "/s/Box", directoryHint: .isDirectory))
    static var inside: String { "/s/Box/\(box.uuidString)/Clipping.txt" }

    static func owned(_ name: String = "Clipping.txt") throws -> ShelfItem {
        try ShelfFixtures.item(
            name, path: "/s/Box/\(box.uuidString)/\(name)", ownership: .owned(relativePath: "\(box.uuidString)/\(name)")
        )
    }

    @Test func anOwnedCopyMovedOutOfStorageBecomesAReference() throws {
        let item = try Self.owned()
        let shelf = try ShelfFixtures.shelf(item)
        let (next, failed) = shelf.relocating(
            [item.id: "/Users/u/Documents/Clipping.txt"], using: FakeBookmarks(), storage: Self.storage)
        #expect(failed.isEmpty)
        #expect(next.items.first?.ownership == .reference && next.items.first?.isOwned == false)
    }

    @Test func anOwnedCopyRenamedInsideStorageStaysOwnedAtItsNewPath() throws {
        let item = try Self.owned()
        let path = "/s/Box/\(Self.box.uuidString)/Note.txt"
        let (next, _) = try ShelfFixtures.shelf(item).relocating(
            [item.id: path], using: FakeBookmarks(), storage: Self.storage)
        #expect(next.items.first?.ownership == .owned(relativePath: "\(Self.box.uuidString)/Note.txt"))
    }

    @Test func aReferenceStaysAReferenceWherever() throws {
        let item = try ShelfFixtures.item("a.txt")
        let (next, _) = try ShelfFixtures.shelf(item).relocating(
            [item.id: Self.inside], using: FakeBookmarks(), storage: Self.storage)
        #expect(next.items.first?.ownership == .reference)
    }

    @Test func aRelocatedItemTakesTheNewFilesIdentitySoItIsFoundAsADuplicate() throws {
        let old = FileIdentity(volumeUUID: "V1", fileID: 1)
        let new = FileIdentity(volumeUUID: "V2", fileID: 7)
        let item = try ShelfFixtures.item("a.txt", path: "/Volumes/A/a.txt", identity: old)
        let fakes = FakeBookmarks(identities: ["/Volumes/B/a.txt": new])
        let (moved, _) = try ShelfFixtures.shelf(item).relocating(
            [item.id: "/Volumes/B/a.txt"], using: fakes, storage: Self.storage)
        #expect(moved.items.first?.identity == new)
        let again = try ShelfFixtures.item("a.txt", path: "/Volumes/B/a.txt", identity: new)
        #expect(moved.adding([again], cap: 10).1.duplicates == ["a.txt"])
    }

    @Test func aStaleOwnedCopyFoundOutsideStorageBecomesAReference() throws {
        let item = try Self.owned()
        let fakes = FakeBookmarks(resolutions: [item.bookmark: .resolved(path: "/Users/u/Clipping.txt", stale: true)])
        let resolved = try ShelfFixtures.shelf(item).resolving(
            with: fakes, maker: fakes, isMounted: { _ in true }, storage: Self.storage)
        #expect(resolved.shelf.items.first?.ownership == .reference)
    }

    @Test(arguments: [
        ".", "./x", "B0/Clipping.txt", box.uuidString, "\(box.uuidString)/", "\(box.uuidString)/.",
        "\(box.uuidString)/..", "\(box.uuidString)/a/b", "\(box.uuidString)//a",
    ])
    func anOwnedPathNamesOneFileInOneBoxFolder(_ relative: String) {
        #expect(throws: ShelfError.ownedPathOutsideBox) {
            try ShelfFixtures.item("a.txt", ownership: .owned(relativePath: relative))
        }
    }

    @Test func aBoxNeverHoldsOneIDTwice() throws {
        let item = try ShelfFixtures.item("a.txt")
        let twin = try ShelfItem(
            id: item.id, bookmark: Data([2]), lastKnownPath: "/y/b.txt", displayName: "b.txt", byteCount: 1,
            addedAt: .t0)
        let (shelf, report) = try Shelf.empty(name: "Box").adding([item, twin], cap: 10)
        #expect(shelf.items.map(\.lastKnownPath) == ["/x/a.txt"] && report.duplicates == ["b.txt"])
    }

    @Test func reorderingCopesWithARepeatedID() throws {
        let shelf = try ShelfFixtures.shelf(names: ["a", "b"])
        let ids = shelf.items.map(\.id)
        #expect(shelf.reordering([ids[1], ids[1], ids[0]]).items.map(\.id) == [ids[1], ids[0]])
    }
}

@Suite("A drop's box is chosen before its copies are written (P2-141)")
struct ShelfDestinationTests {
    @Test func aNewBoxTakesTheIDTheDropWasStoredUnder() throws {
        let id = UUID()
        #expect(ShelfLibrary().destinationID(.current) == nil)
        let (library, _) = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .current, now: .t0, newID: id)
        #expect(library.current?.id == id && library.destinationID(.current) == id)
        #expect(library.destinationID(.newBox) == nil)
        let (more, _) = try library.adding([ShelfFixtures.item("b")], to: .current, now: .t1, newID: UUID())
        #expect(more.current?.id == id && more.boxes.count == 1)
    }

    @Test func ownedPathsListEveryBoxsCopies() throws {
        let copy = try ShelfOwnershipTests.owned()
        let (library, _) = try ShelfLibrary().adding([copy, ShelfFixtures.item("a")], to: .current, now: .t0)
        #expect(library.ownedPaths == ["\(ShelfOwnershipTests.box.uuidString)/Clipping.txt"])
    }
}

import Foundation
import Testing
import ZivletCore

@testable import ZivletShelfCore

@Suite("Shelf (P2-141): add, de-dup, caps, totals")
struct ShelfTests {
    @Test func theSameFileTwiceIsAddedOnce() throws {
        let a = try ShelfFixtures.item("a.txt", identity: FileIdentity(volumeUUID: "V", fileID: 7))
        let again = try ShelfFixtures.item("a renamed.txt", identity: FileIdentity(volumeUUID: "V", fileID: 7))
        let (shelf, report) = try Shelf.empty(name: "Box").adding([a, again], cap: 2_000)
        #expect(shelf.items.count == 1 && report.duplicates == ["a renamed.txt"] && report.added == [a.id])
    }

    @Test func anItemAlreadyInTheBoxIsADuplicate() throws {
        let a = try ShelfFixtures.item("a.txt")
        let shelf = try Shelf.empty(name: "Box").adding([a], cap: 10).0
        let (next, report) = shelf.adding([try ShelfFixtures.item("a.txt")], cap: 10)
        #expect(next.items.count == 1 && report.duplicates == ["a.txt"] && report.added.isEmpty)
    }

    @Test func withoutIdentitiesThePathDecides() throws {
        let a = try ShelfFixtures.item("a.txt", path: "/x/a.txt")
        let b = try ShelfFixtures.item("a.txt", path: "/x/./a.txt")
        #expect(try Shelf.empty(name: "Box").adding([a, b], cap: 10).0.items.count == 1)
    }

    @Test func twoIdentitiesThatDifferAreTwoFilesEvenAtOnePath() throws {
        let a = try ShelfFixtures.item("a.txt", identity: FileIdentity(volumeUUID: "V", fileID: 1))
        let b = try ShelfFixtures.item("a.txt", identity: FileIdentity(volumeUUID: "V", fileID: 2))
        #expect(try Shelf.empty(name: "Box").adding([a, b], cap: 10).0.items.count == 2)
    }

    @Test func itemsOverTheCapAreReportedNotAdded() throws {
        let items = try (0..<5).map { try ShelfFixtures.item("f\($0).txt", path: "/x/f\($0).txt") }
        let (shelf, report) = try Shelf.empty(name: "Box").adding(items, cap: 3)
        #expect(shelf.items.count == 3 && report.overCap == ["f3.txt", "f4.txt"])
        #expect(!report.isEverythingAdded)
    }

    @Test func totalsCountUnknownSizesSeparately() throws {
        let owned = try ShelfFixtures.item(
            "c", size: 5, path: "/c", ownership: .owned(relativePath: "\(ShelfOwnershipTests.box.uuidString)/c"))
        let shelf = try Shelf.empty(name: "Box").adding(
            [try ShelfFixtures.item("a", size: 10), try ShelfFixtures.item("b", size: nil, path: "/b"), owned],
            cap: 10
        ).0
        #expect(shelf.totals == ShelfTotals(count: 3, bytes: 15, ownedBytes: 5, unknownSizes: 1))
    }

    @Test func addingLeavesTheReceiverUnchanged() throws {
        let shelf = try Shelf.empty(name: "Box")
        _ = shelf.adding([try ShelfFixtures.item("a")], cap: 10)
        #expect(shelf.items.isEmpty)
    }

    @Test func removingReturnsANewShelf() throws {
        let shelf = try ShelfFixtures.shelf(names: ["a", "b", "c"])
        let fewer = shelf.removing([shelf.items[1].id])
        #expect(fewer.items.map(\.displayName) == ["a", "c"] && shelf.items.count == 3)
    }

    @Test func reorderingPutsTheNamedItemsFirstAndKeepsTheRest() throws {
        let shelf = try ShelfFixtures.shelf(names: ["a", "b", "c", "d"])
        let ids = shelf.items.map(\.id)
        let moved = shelf.reordering([ids[2], ids[0], UUID()])
        #expect(moved.items.map(\.displayName) == ["c", "a", "b", "d"])
        #expect(shelf.items.map(\.displayName) == ["a", "b", "c", "d"])
    }

    @Test func renamingIsValidated() throws {
        let shelf = try Shelf.empty(name: "Box")
        #expect(try shelf.renamed("Photos").name == "Photos" && shelf.name == "Box")
        #expect(throws: ShelfError.invalidName) { try shelf.renamed("") }
        #expect(throws: ShelfError.invalidName) { try shelf.renamed("a\nb") }
    }

    @Test func placingAndViewingReturnNewShelves() throws {
        let shelf = try Shelf.empty(name: "Box")
        let frame = Rect2D(x: 10, y: 20, width: 300, height: 200)
        let placed = shelf.placed(frame: frame, dock: .right).showing(.list)
        #expect(placed.frame == frame && placed.dock == .right && placed.viewMode == .list)
        #expect(shelf.frame == nil && shelf.dock == nil && shelf.viewMode == .grid)
    }

    @Test func aShelfRoundTripsAndItsDecoderRefusesABadName() throws {
        let frame = Rect2D(x: 1, y: 2, width: 3, height: 4)
        let shelf = try ShelfFixtures.shelf(names: ["a"]).placed(frame: frame, dock: .left)
        let data = try JSONEncoder().encode(shelf)
        #expect(try JSONDecoder().decode(Shelf.self, from: data) == shelf)
        let empty = try JSONEncoder().encode(try Shelf.empty(name: "Box"))
        let bad = empty.replacing(Data(#""Box""#.utf8), with: Data(#""""#.utf8))
        #expect(throws: ShelfError.invalidName) { try JSONDecoder().decode(Shelf.self, from: bad) }
    }
}

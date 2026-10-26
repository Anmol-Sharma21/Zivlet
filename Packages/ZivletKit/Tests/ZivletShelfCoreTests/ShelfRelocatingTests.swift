import Foundation
import Testing

@testable import ZivletShelfCore

@Suite("Box references follow moved files (P2-142 Move to…)")
struct ShelfRelocatingTests {
    @Test func movedItemsCarryTheirNewPathsAndBookmarks() throws {
        let (shelf, _) = try ShelfFixtures.box(present: 3, missing: 0)
        let moved = [shelf.items[0].id: "/Users/u/Done/a.txt", shelf.items[2].id: "/Users/u/Done/c 2.txt"]
        let (next, failed) = shelf.relocating(moved, using: FakeBookmarks())
        #expect(failed.isEmpty)
        #expect(next.items.map(\.lastKnownPath) == ["/Users/u/Done/a.txt", "/x/b.txt", "/Users/u/Done/c 2.txt"])
        #expect(next.items[2].displayName == "c 2.txt" && next.items[2].bookmark == Data("/Users/u/Done/c 2.txt".utf8))
        #expect(next.items.map(\.id) == shelf.items.map(\.id) && shelf.items[0].lastKnownPath == "/x/a.txt")
    }

    @Test func anItemWhoseBookmarkCannotBeMadeKeepsItsOldReference() throws {
        let (shelf, _) = try ShelfFixtures.box(present: 1, missing: 0)
        let id = shelf.items[0].id
        let (next, failed) = shelf.relocating(
            [id: "/Users/u/Done/a.txt"], using: FakeBookmarks(failing: ["/Users/u/Done/a.txt"]))
        #expect(failed == [id] && next == shelf)
    }

    @Test func idsTheBoxDoesNotHoldChangeNothing() throws {
        let (shelf, _) = try ShelfFixtures.box(present: 1, missing: 0)
        let (next, failed) = shelf.relocating([UUID(): "/Users/u/a.txt"], using: FakeBookmarks())
        #expect(next == shelf && failed.isEmpty)
    }
}

import Foundation
import Testing

@testable import ZivletShelfCore

@Suite("Shelf library (OWN-APP-1, D-M5b-18)")
struct ShelfLibraryTests {
    @Test func theFirstDropMakesABoxNamedBox() throws {
        let (lib, report) = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .current, now: .t0)
        #expect(lib.boxes.map(\.name) == ["Box"] && lib.current?.items.count == 1 && report.added.count == 1)
        #expect(lib.current?.updatedAt == .t0)
    }

    @Test func dropsGoToTheMostRecentBox() throws {
        let lib = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .current, now: .t0).0
        let next = try lib.adding([ShelfFixtures.item("b", path: "/b")], to: .current, now: .t1).0
        #expect(next.boxes.count == 1 && next.current?.items.count == 2 && next.current?.updatedAt == .t1)
    }

    @Test func optionMakesANewNumberedBox() throws {
        let lib = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .current, now: .t0).0
        let two = try lib.adding([ShelfFixtures.item("b", path: "/b")], to: .newBox, now: .t1).0
        #expect(two.boxes.map(\.name) == ["Box", "Box 2"] && two.current?.name == "Box 2")
        #expect(lib.boxes.count == 1)
    }

    @Test func aFreedNumberIsUsedAgain() throws {
        var lib = ShelfLibrary()
        for i in 0..<3 { lib = try lib.adding([ShelfFixtures.item("f\(i)")], to: .newBox, now: .t0).0 }
        let box2 = try #require(lib.boxes.first { $0.name == "Box 2" })
        let again = try lib.removingBox(box2.id).adding([ShelfFixtures.item("g")], to: .newBox, now: .t1).0
        #expect(again.boxes.map(\.name).sorted() == ["Box", "Box 2", "Box 3"])
    }

    @Test func aNinthBoxIsRefused() throws {
        var lib = ShelfLibrary()
        for i in 0..<8 { lib = try lib.adding([ShelfFixtures.item("f\(i)", path: "/f\(i)")], to: .newBox, now: .t0).0 }
        #expect(lib.boxes.count == ShelfLibrary.maxBoxes)
        #expect(throws: ShelfError.tooManyBoxes) {
            try lib.adding([ShelfFixtures.item("g", path: "/g")], to: .newBox, now: .t1)
        }
    }

    @Test func aFullBoxReportsTheItemsItCouldNotTake() throws {
        let items = try (0..<(ShelfLibrary.maxItemsPerBox + 2)).map { try ShelfFixtures.item("f\($0)") }
        let (lib, report) = try ShelfLibrary().adding(items, to: .current, now: .t0)
        #expect(lib.current?.items.count == ShelfLibrary.maxItemsPerBox && report.overCap.count == 2)
    }

    @Test func removingTheCurrentBoxMakesTheMostRecentOtherCurrent() throws {
        var lib = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .newBox, now: .t0).0
        lib = try lib.adding([ShelfFixtures.item("b")], to: .newBox, now: .t1).0
        lib = try lib.adding([ShelfFixtures.item("c")], to: .newBox, now: .t0.addingTimeInterval(1)).0
        let current = try #require(lib.current)
        let after = lib.removingBox(current.id)
        #expect(after.boxes.count == 2 && after.current?.name == "Box 2")
        #expect(lib.boxes.count == 3 && lib.current == current)
    }

    @Test func removingAnotherBoxKeepsTheCurrentOne() throws {
        var lib = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .newBox, now: .t0).0
        lib = try lib.adding([ShelfFixtures.item("b")], to: .newBox, now: .t1).0
        let first = lib.boxes[0]
        #expect(lib.removingBox(first.id).current?.name == "Box 2")
        #expect(lib.removingBox(lib.boxes[1].id).removingBox(first.id).current == nil)
    }

    @Test func makingCurrentAndReplacingReturnNewLibraries() throws {
        var lib = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .newBox, now: .t0).0
        lib = try lib.adding([ShelfFixtures.item("b")], to: .newBox, now: .t1).0
        let first = lib.boxes[0]
        let switched = lib.makingCurrent(first.id)
        #expect(switched.current?.id == first.id && lib.current?.id != first.id)
        #expect(lib.makingCurrent(UUID()) == lib)
        let renamed = try first.renamed("Photos")
        #expect(lib.replacing(renamed).boxes[0].name == "Photos" && lib.boxes[0].name == "Box")
        #expect(lib.replacing(try Shelf.empty(name: "Stranger")) == lib)
    }

    @Test func aCurrentIDThatNamesNoBoxIsDropped() throws {
        let box = try Shelf.empty(name: "Box")
        #expect(ShelfLibrary(boxes: [box], currentID: UUID()).current == nil)
        #expect(ShelfLibrary(boxes: [box], currentID: box.id).current == box)
    }
}

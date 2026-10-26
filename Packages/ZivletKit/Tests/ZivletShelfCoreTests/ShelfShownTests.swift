import Foundation
import Testing
import ZivletCore

@testable import ZivletShelfCore

@Suite("A box remembers how its panel was shown (P2-55 §9.5)")
struct ShelfShownTests {
    @Test func aNewBoxIsHidden() throws { #expect(try Shelf.empty(name: "Box").shown == .hidden) }

    @Test(arguments: [
        BoxPresentation.Base.hidden, .collapsed, .expanded, .docked(.left), .docked(.right),
    ])
    func everyBaseRoundTrips(_ base: BoxPresentation.Base) throws {
        let shelf = try Shelf.empty(name: "Box").presented(base)
        let decoded = try JSONDecoder().decode(Shelf.self, from: JSONEncoder().encode(shelf))
        #expect(decoded.shown == base && decoded == shelf)
    }

    @Test func aFileWithoutTheFieldDecodesAsHidden() throws {
        let json = """
            {"id":"\(UUID().uuidString)","name":"Box","items":[],"viewMode":"grid","updatedAt":0}
            """
        #expect(try JSONDecoder().decode(Shelf.self, from: Data(json.utf8)).shown == .hidden)
    }

    @Test func anUnknownValueDecodesAsHidden() throws {
        let json = """
            {"id":"\(UUID().uuidString)","name":"Box","items":[],"viewMode":"grid","updatedAt":0,"shown":"sideways"}
            """
        #expect(try JSONDecoder().decode(Shelf.self, from: Data(json.utf8)).shown == .hidden)
    }

    @Test func theStoreKeepsTheShownBase() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "zivlet-shown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BoxStore(file: folder.appending(path: "boxes.json"))
        let shelf = try Shelf.empty(name: "Box").presented(.docked(.right)).placed(frame: nil, dock: .right)
        try store.save(ShelfLibrary(boxes: [shelf], currentID: shelf.id))
        guard case .loaded(let library, 0) = store.load() else {
            Issue.record("not loaded")
            return
        }
        #expect(library.current?.shown == .docked(.right) && library.current?.dock == .right)
    }
}

@Suite("A resolution made off the main thread lands on the box as it is now (G-M5b-8)")
struct ShelfRefreshedItemsTests {
    @Test func theRefreshedItemsArriveAndTheBoxKeepsItsPlaceAndState() throws {
        let asked = try ShelfFixtures.shelf(names: ["a.txt", "b.txt"])
        let now = asked.presented(.expanded).placed(frame: Rect2D(x: 1, y: 2, width: 3, height: 4), dock: nil)
        let refreshed = asked.removing([asked.items[0].id])
        let next = now.withItems(of: refreshed)
        #expect(next.items == refreshed.items && next.shown == .expanded && next.frame == now.frame)
        #expect(next.id == now.id && next.name == now.name)
    }
}

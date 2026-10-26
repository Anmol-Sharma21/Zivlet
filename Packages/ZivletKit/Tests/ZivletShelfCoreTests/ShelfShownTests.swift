import Foundation
import Testing

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

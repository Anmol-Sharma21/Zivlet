import Foundation
import TestSupport
import Testing

@testable import ZivletShelfCore

@Suite("Box store (P2-141: boxes.json 0600, atomic, schema-versioned)")
struct BoxStoreTests {
    private func mode(_ url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }

    /// `{"schema":1,"boxes":[…]}` around boxes encoded the way the store encodes them.
    private func storedJSON(_ boxes: [Shelf], current: UUID? = nil) throws -> String {
        let encoded = String(decoding: try JSONEncoder().encode(boxes), as: UTF8.self)
        let currentField = current.map { #","current":"\#($0.uuidString)""# } ?? ""
        return #"{"schema":1,"boxes":\#(encoded)\#(currentField)}"#
    }

    @Test func noFileIsAnEmptyLibrary() throws {
        let dir = try TempDir()
        #expect(BoxStore(file: dir.url.appending(path: "boxes.json")).load() == .empty)
    }

    @Test func aSavedLibraryIsPrivateAndRoundTrips() throws {
        let dir = try TempDir()
        let store = BoxStore(file: dir.url.appending(path: "Zivlet/boxes.json"))
        let lib = try ShelfFixtures.libraryWithTwoBoxes()
        try store.save(lib)
        #expect(try mode(store.file) == 0o600)
        #expect(try mode(store.file.deletingLastPathComponent()) == 0o700)
        #expect(store.load() == .loaded(lib, dropped: 0))
    }

    @Test func savingAgainReplacesTheFileAndLeavesNoTemporaryFiles() throws {
        let dir = try TempDir()
        let store = BoxStore(file: dir.url.appending(path: "boxes.json"))
        try store.save(try ShelfFixtures.libraryWithTwoBoxes())
        try store.save(ShelfLibrary())
        #expect(store.load() == .loaded(ShelfLibrary(), dropped: 0))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.path) == ["boxes.json"])
        #expect(try mode(store.file) == 0o600)
    }

    @Test func theFileSaysItsSchema() throws {
        let dir = try TempDir()
        let store = BoxStore(file: dir.url.appending(path: "boxes.json"))
        try store.save(ShelfLibrary())
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any]
        #expect(object?["schema"] as? Int == BoxStore.schema)
    }

    @Test(arguments: ["{not json", "[]", #"{"boxes":[]}"#, #"{"schema":0,"boxes":[]}"#, #"{"schema":1}"#])
    func unreadableJSONIsMovedAsideAndTheBoxStartsEmpty(_ contents: String) throws {
        let dir = try TempDir()
        try dir.file("boxes.damaged.json", "an older damaged file")
        let store = BoxStore(file: try dir.file("boxes.json", contents))
        #expect(store.load() == .damaged)
        let older = dir.url.appending(path: "boxes.damaged.json")
        let aside = dir.url.appending(path: "boxes.damaged 2.json")
        #expect(try String(contentsOf: older, encoding: .utf8) == "an older damaged file")
        #expect(try String(contentsOf: aside, encoding: .utf8) == contents)
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
        #expect(store.load() == .empty)
    }

    @Test func aFileThatCannotBeReadIsLeftAloneAndNeverOverwritten() throws {
        let dir = try TempDir()
        let file = try dir.file("boxes.json", #"{"schema":1,"boxes":[]}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        let store = BoxStore(file: file)
        #expect(store.load() == .unreadable)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: dir.url.appending(path: "boxes.damaged.json").path))
        #expect(BoxLoad.unreadable.notice != nil && BoxLoad.damaged.notice != nil)
    }

    @Test func aLossyLoadKeepsACopyOfTheFileAsItWas() throws {
        let box = try ShelfFixtures.shelf(ShelfFixtures.item("a", bookmark: Data([7, 7, 7])), ShelfFixtures.item("b"))
        let firstBookmark = try JSONEncoder().encode(box.items[0].bookmark)
        let broken = try storedJSON([box], current: box.id).replacingOccurrences(
            of: String(decoding: firstBookmark, as: UTF8.self), with: #""""#)
        let dir = try TempDir()
        let load = BoxStore(file: try dir.file("boxes.json", broken)).load()
        guard case .loaded(_, let dropped) = load else {
            Issue.record("the library did not load")
            return
        }
        let kept = try String(contentsOf: dir.url.appending(path: "boxes.before-repair.json"), encoding: .utf8)
        #expect(dropped == 1 && kept == broken)
        #expect(load.notice != nil && BoxLoad.loaded(ShelfLibrary(), dropped: 0).notice == nil)
    }

    @Test func aNewerFileWrittenAfterASaveIsStillNeverOverwritten() throws {
        let dir = try TempDir()
        let store = BoxStore(file: dir.url.appending(path: "boxes.json"))
        try store.save(ShelfLibrary())
        try store.save(ShelfLibrary())
        try Data(#"{"schema":2,"boxes":[],"later":true}"#.utf8).write(to: store.file)
        #expect(throws: BoxStoreError.wouldOverwriteNewer) { try store.save(ShelfLibrary()) }
    }

    @Test func twoItemsWithOneIDKeepTheFirst() throws {
        let item = try ShelfFixtures.item("a")
        let twin = try ShelfItem(
            id: item.id, bookmark: Data([9]), lastKnownPath: "/y/b", displayName: "b", byteCount: 1, addedAt: .t0)
        let both = try Shelf(name: "Box", items: [item, twin], updatedAt: .t0)
        let dir = try TempDir()
        let load = BoxStore(file: try dir.file("boxes.json", try storedJSON([both]))).load()
        let once = try Shelf(id: both.id, name: "Box", items: [item], updatedAt: .t0)
        #expect(load == .loaded(ShelfLibrary(boxes: [once]), dropped: 1))
    }

    @Test func aNewerSchemaIsNeverOverwritten() throws {
        let dir = try TempDir()
        let file = try dir.file("boxes.json", #"{"schema":2,"boxes":[]}"#)
        let store = BoxStore(file: file)
        #expect(store.load() == .newer(schema: 2))
        #expect(throws: BoxStoreError.wouldOverwriteNewer) { try store.save(ShelfLibrary()) }
        #expect(try String(contentsOf: file, encoding: .utf8) == #"{"schema":2,"boxes":[]}"#)
    }

    @Test func invalidItemsAreDroppedAndCounted() throws {
        let box = try ShelfFixtures.shelf(ShelfFixtures.item("a", bookmark: Data([7, 7, 7])), ShelfFixtures.item("b"))
        let json = try storedJSON([box], current: box.id)
        let firstBookmark = try JSONEncoder().encode(box.items[0].bookmark)
        let broken = json.replacingOccurrences(
            of: String(decoding: firstBookmark, as: UTF8.self), with: #""""#)
        let dir = try TempDir()
        let store = BoxStore(file: try dir.file("boxes.json", broken))
        guard case .loaded(let lib, let dropped) = store.load() else {
            Issue.record("the library did not load")
            return
        }
        #expect(dropped == 1 && lib.current?.items.map(\.displayName) == ["b"])
    }

    @Test func aBoxWithABadNameIsDroppedAndCounted() throws {
        let good = try ShelfFixtures.shelf(names: ["a"], name: "Keep")
        let bad = try ShelfFixtures.shelf(names: ["b"], name: "Drop")
        let json = try storedJSON([good, bad]).replacingOccurrences(of: #""Drop""#, with: #""""#)
        let dir = try TempDir()
        let load = BoxStore(file: try dir.file("boxes.json", json)).load()
        #expect(load == .loaded(ShelfLibrary(boxes: [good]), dropped: 1))
    }

    @Test func boxesAndItemsOverTheCapsAreDroppedAndCounted() throws {
        let boxes = try (0..<9).map { try ShelfFixtures.shelf(names: ["f\($0)"], name: "B\($0)") }
        let dir = try TempDir()
        let load = BoxStore(file: try dir.file("boxes.json", try storedJSON(boxes))).load()
        #expect(load == .loaded(ShelfLibrary(boxes: Array(boxes.prefix(8))), dropped: 1))
    }

    @Test func aDuplicateItemOnDiskIsDroppedAndCounted() throws {
        let item = try ShelfFixtures.item("a")
        let twice = try Shelf(name: "Box", items: [item, item], updatedAt: .t0)
        let dir = try TempDir()
        let load = BoxStore(file: try dir.file("boxes.json", try storedJSON([twice]))).load()
        let once = try Shelf(id: twice.id, name: "Box", items: [item], updatedAt: .t0)
        #expect(load == .loaded(ShelfLibrary(boxes: [once]), dropped: 1))
    }

    @Test func aCurrentIDThatNamesNoBoxIsForgotten() throws {
        let box = try ShelfFixtures.shelf(names: ["a"])
        let dir = try TempDir()
        let load = BoxStore(file: try dir.file("boxes.json", try storedJSON([box], current: UUID()))).load()
        #expect(load == .loaded(ShelfLibrary(boxes: [box]), dropped: 0))
    }

    @Test func aFolderThatCannotBeMadeIsAWriteFailure() throws {
        let dir = try TempDir()
        let blocker = try dir.file("blocker", "a file where the folder should be")
        let store = BoxStore(file: blocker.appending(path: "boxes.json"))
        #expect(throws: BoxStoreError.writeFailed) { try store.save(ShelfLibrary()) }
    }

    @Test func theStandardFileLivesInApplicationSupport() {
        let path = BoxStore.standard().file.path
        #expect(path.hasSuffix("Application Support/Zivlet/boxes.json"))
    }

    @Test func errorsSpeakZivletsWords() {
        #expect(BoxStoreError.wouldOverwriteNewer.userMessage != BoxStoreError.writeFailed.userMessage)
        #expect(!BoxStoreError.writeFailed.userMessage.isEmpty)
    }
}

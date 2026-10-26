import Foundation
import TestSupport
import Testing

@testable import ZivletShelfCore

@Suite("Owned copies (P2-141): names, folders, sizes")
struct OwnedStorageTests {
    @Test func aBoxHasItsOwnFolderUnderTheRoot() throws {
        let dir = try TempDir()
        let storage = OwnedStorage(root: dir.url)
        let box = UUID()
        #expect(storage.folder(for: box).path == dir.url.appending(path: box.uuidString).path)
    }

    @Test func reservingMakesTheBoxFolderPrivate() throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let box = UUID()
        let url = try storage.reserve(name: "Clipping.txt", in: box)
        #expect(url.lastPathComponent == "Clipping.txt")
        #expect(url.deletingLastPathComponent().standardizedFileURL == storage.folder(for: box).standardizedFileURL)
        let mode = try FileManager.default.attributesOfItem(atPath: storage.folder(for: box).path)[.posixPermissions]
        #expect(mode as? Int == 0o700)
    }

    @Test func aClashGetsTheNextFreeName() throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let box = UUID()
        let first = try storage.reserve(name: "Clipping.txt", in: box)
        try Data().write(to: first)
        let second = try storage.reserve(name: "Clipping.txt", in: box)
        #expect(second.lastPathComponent == "Clipping 2.txt")
        try Data().write(to: second)
        #expect(try storage.reserve(name: "Clipping.txt", in: box).lastPathComponent == "Clipping 3.txt")
    }

    @Test func aNameWithoutAnExtensionIsNumberedToo() throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let box = UUID()
        try Data().write(to: try storage.reserve(name: "Notes", in: box))
        #expect(try storage.reserve(name: "Notes", in: box).lastPathComponent == "Notes 2")
    }

    @Test(arguments: ["../escape.txt", "/etc/passwd", "a/../../b", "..", ".hidden"])
    func aNameCannotLeaveTheBoxFolder(_ name: String) throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let box = UUID()
        let url = try? storage.reserve(name: name, in: box)
        let folder = storage.folder(for: box).standardizedFileURL.path + "/"
        #expect(url == nil || url?.standardizedFileURL.path.hasPrefix(folder) == true)
        #expect(url?.lastPathComponent.hasPrefix(".") != true)
    }

    @Test(arguments: ["", "...", "\n", String(repeating: "a", count: 300)])
    func anUnusableNameIsRefused(_ name: String) throws {
        let storage = OwnedStorage(root: try TempDir().url)
        #expect(throws: ShelfError.invalidName) { try storage.reserve(name: name, in: UUID()) }
    }

    @Test func aRootThatCannotBeMadeIsAStorageFailure() throws {
        let dir = try TempDir()
        let storage = OwnedStorage(root: try dir.file("blocker", "a file where the folder should be"))
        #expect(throws: ShelfError.storageFailed) { try storage.reserve(name: "a.txt", in: UUID()) }
    }

    @Test func relativePathsRoundTripAndStayInside() throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let box = UUID()
        let url = try storage.reserve(name: "a.txt", in: box)
        let relative = try #require(storage.relativePath(of: url))
        #expect(relative == "\(box.uuidString)/a.txt")
        #expect(try storage.url(forRelativePath: relative).standardizedFileURL == url.standardizedFileURL)
        #expect(throws: ShelfError.ownedPathOutsideBox) { try storage.url(forRelativePath: "../x") }
        #expect(storage.relativePath(of: URL(filePath: "/tmp/elsewhere.txt")) == nil)
    }

    @Test func bytesAreCountedPerBoxAndInAll() throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let one = UUID()
        let two = UUID()
        try Data(count: 100).write(to: try storage.reserve(name: "a", in: one))
        try Data(count: 50).write(to: try storage.reserve(name: "b", in: one))
        try Data(count: 7).write(to: try storage.reserve(name: "c", in: two))
        #expect(storage.bytes(in: one) == 150 && storage.bytes(in: two) == 7 && storage.allBytes() == 157)
        #expect(storage.bytes(in: UUID()) == 0)
    }

    @Test func theStandardRootLivesInApplicationSupport() {
        #expect(OwnedStorage.standard().root.path.hasSuffix("Application Support/Zivlet/Box"))
    }

    @Test func trashingSomethingThatIsGoneFailsWithZivletsWords() {
        let gone = URL(filePath: "/nonexistent-\(UUID().uuidString)/a.txt")
        #expect(throws: ShelfError.trashFailed) { try SystemTrash().trash(gone) }
        #expect(!ShelfError.trashFailed.userMessage.isEmpty)
    }
}

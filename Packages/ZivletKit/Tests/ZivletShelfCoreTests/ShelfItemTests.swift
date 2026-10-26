import Foundation
import Testing

@testable import ZivletShelfCore

@Suite("Shelf item (P2-141): immutable, validated at the boundary")
struct ShelfItemTests {
    @Test func aValidItemKeepsItsValues() throws {
        let item = try ShelfFixtures.item("photo.heic", size: 2_100_000)
        #expect(item.displayName == "photo.heic" && item.ownership == .reference && item.byteCount == 2_100_000)
        #expect(item.lastKnownPath == "/x/photo.heic" && item.addedAt == .t0 && item.identity == nil)
    }

    @Test(arguments: [Data(), Data(count: 16_385)])
    func badBookmarksAreRefused(_ bookmark: Data) {
        #expect(throws: ShelfError.self) { try ShelfFixtures.item("a.txt", bookmark: bookmark) }
    }

    @Test func theLargestBookmarkIsAccepted() throws {
        #expect(try ShelfFixtures.item("a.txt", bookmark: Data(count: 16_384)).bookmark.count == 16_384)
    }

    @Test(arguments: ["", "a/b", "line\nbreak", "tab\there", String(repeating: "é", count: 128)])
    func badNamesAreRefused(_ name: String) {
        #expect(throws: ShelfError.invalidName) { try ShelfFixtures.item(name, path: "/x/a") }
    }

    @Test func aNameOf255BytesIsAccepted() throws {
        let name = String(repeating: "a", count: 255)
        #expect(try ShelfFixtures.item(name, path: "/x/a").displayName == name)
    }

    @Test func aRelativeLastKnownPathIsRefused() {
        #expect(throws: ShelfError.relativePath("Downloads/a.txt")) {
            try ShelfFixtures.item("a.txt", path: "Downloads/a.txt")
        }
    }

    @Test func anOverlongOrNulPathIsRefused() {
        #expect(throws: ShelfError.invalidPath) {
            try ShelfFixtures.item("a.txt", path: "/" + String(repeating: "a", count: 4_096))
        }
        #expect(throws: ShelfError.invalidPath) { try ShelfFixtures.item("a.txt", path: "/a\u{0}b") }
    }

    @Test func aNegativeSizeIsRefused() {
        #expect(throws: ShelfError.negativeSize) { try ShelfFixtures.item("a.txt", size: -1) }
    }

    @Test(arguments: ["../x", "a/../../x", "/abs/x", "", "a/\u{0}"])
    func anOwnedPathMayNotLeaveItsFolder(_ relative: String) {
        #expect(throws: ShelfError.ownedPathOutsideBox) {
            try ShelfFixtures.item("a.txt", ownership: .owned(relativePath: relative))
        }
    }

    @Test func anOwnedPathInsideItsFolderIsAccepted() throws {
        let item = try ShelfFixtures.item("a.txt", ownership: .owned(relativePath: "B0/Clipping.txt"))
        #expect(item.ownership == .owned(relativePath: "B0/Clipping.txt") && item.isOwned)
    }

    @Test func anEmptyVolumeIdentityIsRefused() {
        #expect(throws: ShelfError.invalidIdentity) {
            try ShelfFixtures.item("a.txt", identity: FileIdentity(volumeUUID: "", fileID: 1))
        }
    }

    @Test func relocatingReturnsANewItemAndLeavesTheOldOne() throws {
        let item = try ShelfFixtures.item("a.txt", path: "/Users/u/Downloads/a.txt")
        let moved = try item.relocated(to: "/Users/u/Desktop/b.txt", bookmark: Data([2]))
        #expect(moved.lastKnownPath.hasSuffix("Desktop/b.txt") && item.lastKnownPath.hasSuffix("Downloads/a.txt"))
        #expect(moved.id == item.id && moved.bookmark == Data([2]) && item.bookmark == Data([1]))
        #expect(moved.displayName == "b.txt" && item.displayName == "a.txt")
    }

    @Test func relocatingRunsTheSameRules() throws {
        let item = try ShelfFixtures.item("a.txt")
        #expect(throws: ShelfError.relativePath("b.txt")) { try item.relocated(to: "b.txt", bookmark: Data([2])) }
        #expect(throws: ShelfError.self) { try item.relocated(to: "/b.txt", bookmark: Data()) }
    }

    @Test func aNewSizeIsANewItem() throws {
        let item = try ShelfFixtures.item("a.txt", size: 1)
        let sized = try item.withSize(nil)
        #expect(sized.byteCount == nil && item.byteCount == 1)
        #expect(throws: ShelfError.negativeSize) { try item.withSize(-5) }
    }

    @Test func anItemRoundTripsThroughJSON() throws {
        let item = try ShelfFixtures.item(
            "a.txt", ownership: .owned(relativePath: "B/a.txt"), identity: FileIdentity(volumeUUID: "V", fileID: 9))
        let decoded = try JSONDecoder().decode(ShelfItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }

    @Test func decodingRunsTheSameRules() throws {
        let json =
            #"{"id":"6F1E2B9C-0000-4000-8000-000000000001","bookmark":"","lastKnownPath":"/a","displayName":"a","#
            + #""addedAt":0,"ownership":{"reference":{}}}"#
        #expect(throws: ShelfError.badBookmark) { try JSONDecoder().decode(ShelfItem.self, from: Data(json.utf8)) }
    }

    @Test func everyErrorSpeaksZivletsWords() {
        let all: [ShelfError] = [
            .badBookmark, .relativePath("a"), .invalidPath, .invalidName, .negativeSize, .ownedPathOutsideBox,
            .invalidIdentity, .tooManyBoxes, .notAFileURL, .bookmarkFailed, .trashFailed, .storageFailed,
        ]
        for error in all { #expect(!error.userMessage.isEmpty && !error.userMessage.contains("/")) }
        #expect(Set(all.map(\.userMessage)).count == all.count)
    }
}

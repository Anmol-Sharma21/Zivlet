import Foundation
import TestSupport
import Testing

@testable import ZivletShelfCore

@Suite("System bookmarks on real files (D-M5b-2)", .serialized)
struct SystemBookmarksTests {
    let bookmarks = SystemBookmarks()
    let mounted: @Sendable (String) -> Bool = { _ in true }

    /// The temporary folder sits behind the /var → /private/var link; resolution answers the real path, which
    /// `resolvingSymlinksInPath` would shorten again, so ask `realpath`.
    private func real(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    @Test func anItemMadeFromAFileKnowsItsNameSizeAndIdentity() throws {
        let dir = try TempDir()
        let file = try dir.file("a.txt", "hello")
        let item = try ShelfItem.referencing(file, using: bookmarks, now: .t0)
        #expect(item.displayName == "a.txt" && item.byteCount == 5 && item.identity != nil)
        #expect(item.lastKnownPath == file.path && item.ownership == .reference && item.addedAt == .t0)
    }

    @Test func aFolderHasNoSize() throws {
        let dir = try TempDir()
        #expect(bookmarks.size(of: try dir.folder("inner")) == nil)
    }

    @Test func aRenamedAndMovedFileResolvesStaleThenFresh() throws {
        let dir = try TempDir()
        let file = try dir.file("a.txt", "x")
        let item = try ShelfItem.referencing(file, using: bookmarks, now: .t0)
        let moved = try dir.folder("other").appending(path: "a renamed.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        let first = try ShelfFixtures.shelf(item).resolving(
            with: bookmarks, maker: bookmarks, isMounted: mounted, storage: ShelfOwnershipTests.storage)
        #expect(first.statuses[item.id] == .present(path: real(moved)))
        #expect(first.shelf.items.first?.displayName == "a renamed.txt")
        let again = first.shelf.resolving(
            with: bookmarks, maker: bookmarks, isMounted: mounted, storage: ShelfOwnershipTests.storage)
        #expect(again.shelf == first.shelf)  // nothing stale the second time
    }

    @Test func aFileMovedIntoAFolderNamedTrashIsInTheTrash() throws {
        let dir = try TempDir()
        let file = try dir.file("a.txt", "x")
        let item = try ShelfItem.referencing(file, using: bookmarks, now: .t0)
        let trashed = try dir.folder(".Trash").appending(path: "a.txt")
        try FileManager.default.moveItem(at: file, to: trashed)
        let resolved = try ShelfFixtures.shelf(item).resolving(
            with: bookmarks, maker: bookmarks, isMounted: mounted, storage: ShelfOwnershipTests.storage)
        #expect(resolved.statuses[item.id] == .inTrash(path: real(trashed)))
    }

    @Test func aDeletedFileIsMissing() throws {
        let dir = try TempDir()
        let file = try dir.file("a.txt", "x")
        let item = try ShelfItem.referencing(file, using: bookmarks, now: .t0)
        try FileManager.default.removeItem(at: file)
        let resolution = bookmarks.resolve(item.bookmark)
        guard case .failed(let code, let volumePath, _) = resolution else {
            Issue.record("a deleted file resolved: \(resolution)")
            return
        }
        #expect(code == 4 && volumePath != nil)
        #expect(ItemStatus.from(resolution, isMounted: SystemBookmarks.isMounted) == .missing)
    }

    @Test func garbageResolvesToAFailure() {
        guard case .failed = bookmarks.resolve(Data([1, 2, 3])) else {
            Issue.record("three bytes resolved")
            return
        }
    }

    @Test func onlyFileURLsAreBookmarked() throws {
        #expect(throws: ShelfError.notAFileURL) {
            try ShelfItem.referencing(try #require(URL(string: "https://example.com/a")), using: bookmarks, now: .t0)
        }
        #expect(throws: ShelfError.bookmarkFailed) {
            try bookmarks.bookmark(for: URL(filePath: "/nonexistent-\(UUID().uuidString)/a.txt"))
        }
    }

    @Test func theRootVolumeIsMounted() {
        #expect(SystemBookmarks.isMounted("/") && !SystemBookmarks.isMounted("/Volumes/Gone-\(UUID().uuidString)"))
    }

    @Test func theOptionsAreNeverSecurityScoped() {
        #expect(!SystemBookmarks.creationOptions.contains(.withSecurityScope))
        #expect(SystemBookmarks.creationOptions.contains(.withoutImplicitSecurityScope))
        #expect(SystemBookmarks.resolutionOptions == [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing])
    }
}

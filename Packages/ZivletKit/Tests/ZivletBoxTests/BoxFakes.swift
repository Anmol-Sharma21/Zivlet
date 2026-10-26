import AppKit
import Foundation
import Testing
import ZivletShelfCore

@testable import ZivletBox

/// Bookmarks as the path's bytes; resolution scripted per bookmark (present at its own path by default); counts
/// resolutions so restore tests can prove nothing was resolved at launch.
final class FakeBoxBookmarks: BookmarkMaking, BookmarkResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var _resolveCalls = 0
    private var _makeCalls = 0
    var resolutions: [String: Resolution] = [:]

    var resolveCalls: Int { lock.withLock { _resolveCalls } }
    var makeCalls: Int { lock.withLock { _makeCalls } }

    func bookmark(for url: URL) throws(ShelfError) -> Data {
        lock.withLock { _makeCalls += 1 }
        return Data(url.path.utf8)
    }

    func identity(of url: URL) -> FileIdentity? { nil }
    func size(of url: URL) -> Int64? { 1_000 }

    func resolve(_ bookmark: Data) -> Resolution {
        lock.withLock { _resolveCalls += 1 }
        let path = String(decoding: bookmark, as: UTF8.self)
        return resolutions[path] ?? .resolved(path: path, stale: false)
    }
}

/// A bookmark maker that fails the test when called: pre-drop reads must stay on the pasteboard (D-M5b-4).
struct FailingBookmarks: BookmarkMaking {
    func bookmark(for url: URL) throws(ShelfError) -> Data {
        Issue.record("a bookmark was made before the drop")
        throw .bookmarkFailed
    }

    func identity(of url: URL) -> FileIdentity? {
        Issue.record("an identity was read before the drop")
        return nil
    }

    func size(of url: URL) -> Int64? {
        Issue.record("a size was read before the drop")
        return nil
    }
}

/// Promises received by writing the named files into the destination.
@MainActor
final class FakePromises: PromiseReceiving {
    let names: [String]
    private(set) var calls = 0

    init(names: [String]) { self.names = names }

    func hasPromises(on pasteboard: NSPasteboard) -> Bool { !names.isEmpty }

    func receivePromises(from pasteboard: NSPasteboard, into folder: URL) async -> PromiseOutcome {
        calls += 1
        let files = names.map { folder.appending(path: $0) }
        for file in files { try? Data("promised".utf8).write(to: file) }
        return PromiseOutcome(received: files, failed: 0)
    }
}

/// A private pasteboard, released at the end of the test.
@MainActor
final class TestPasteboard {
    let board = NSPasteboard(name: NSPasteboard.Name("app.zivlet.test.\(UUID().uuidString)"))

    init(urls: [URL] = [], string: String? = nil, image: NSImage? = nil) {
        board.clearContents()
        var objects: [any NSPasteboardWriting] = urls.map { $0 as NSURL }
        if let string { objects.append(string as NSString) }
        if let image { objects.append(image) }
        if !objects.isEmpty { board.writeObjects(objects) }
    }

    isolated deinit { board.releaseGlobally() }
}

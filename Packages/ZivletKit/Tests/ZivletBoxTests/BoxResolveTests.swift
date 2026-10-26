import AppKit
import TestSupport
import Testing
import ZivletShelfCore

@testable import ZivletBox

/// Fake bookmarks that, once armed, hold the first resolve or bookmark call until `release()`. A call made on the
/// main thread would block the test that waits for it, so a hold gives up after two seconds and disarms; `isHeld`
/// is true only while a call waits.
final class HoldingBookmarks: BookmarkMaking, BookmarkResolving, @unchecked Sendable {
    let base: FakeBoxBookmarks
    private let lock = NSCondition()
    private var armed = false
    private var held = false
    private var released = false

    init(_ base: FakeBoxBookmarks) { self.base = base }

    var isHeld: Bool { lock.withLock { held } }

    func arm() { lock.withLock { armed = true } }

    func release() {
        lock.withLock {
            released = true
            lock.broadcast()
        }
    }

    func bookmark(for url: URL) throws(ShelfError) -> Data {
        hold()
        return try base.bookmark(for: url)
    }

    func identity(of url: URL) -> FileIdentity? { base.identity(of: url) }
    func size(of url: URL) -> Int64? { base.size(of: url) }

    func resolve(_ bookmark: Data) -> Resolution {
        hold()
        return base.resolve(bookmark)
    }

    private func hold() {
        lock.withLock {
            guard armed, !released else { return }
            held = true
            let limit = Date().addingTimeInterval(2)
            while !released, lock.wait(until: limit) {}
            held = false
            armed = false
        }
    }
}

@Suite("The box resolves and takes promises off the main thread (G-M5b-8)")
@MainActor
struct BoxResolveTests {
    static func box(_ rig: BoxRig, files count: Int) async throws -> (BoxController, [URL], HoldingBookmarks) {
        let holding = HoldingBookmarks(rig.bookmarks)
        rig.resolver = holding
        let box = rig.controller()
        box.start()
        let files = try rig.files(count)
        _ = await box.add(files, newBox: false)
        return (box, files, holding)
    }

    @Test func showDrawsBeforeResolvingAndAppliesTheResultAfter() async throws {
        let rig = try BoxRig()
        let (box, files, holding) = try await Self.box(rig, files: 3)
        rig.bookmarks.resolutions[files[1].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: nil, storedVolumeName: nil)
        holding.arm()
        box.showPanel()
        #expect(box.panel.isVisible && box.presentation.missing == 0)
        try await waitUntil { holding.isHeld }
        holding.release()
        try await waitUntil { box.presentation.missing == 1 }
        #expect(box.viewModel.items.count == 3)
        box.hidePanel()
    }

    @Test func anItemRemovedWhileResolvingIsNotBroughtBack() async throws {
        let rig = try BoxRig()
        let (box, files, holding) = try await Self.box(rig, files: 3)
        rig.bookmarks.resolutions[files[2].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: nil, storedVolumeName: nil)
        holding.arm()
        box.showPanel()
        try await waitUntil { holding.isHeld }
        let first = try #require(box.current?.items.first)
        box.remove([first], from: try #require(box.current))
        holding.release()
        try await waitUntil { box.presentation.missing == 1 }
        #expect(box.current?.items.map(\.displayName) == ["f1.txt", "f2.txt"])
        #expect(rig.saved()?.current?.items.count == 2)
        box.hidePanel()
    }

    @Test func twentyPromisedFilesBecomeItemsWithoutHoldingTheMainActor() async throws {
        let dir = try TempDir()
        let holding = HoldingBookmarks(FakeBoxBookmarks())
        let intake = BoxIntake(
            maker: holding, storage: OwnedStorage(root: dir.url.appending(path: "Box")),
            promises: FakePromises(names: (0..<20).map { "mail\($0).eml" }))
        let pasteboard = TestPasteboard()
        holding.arm()
        let running = Task { await intake.receive(from: pasteboard.board, box: UUID()) }
        try await waitUntil { holding.isHeld }
        let probe = Task { @MainActor in true }
        #expect(await probe.value)
        holding.release()
        let result = await running.value
        #expect(result.items.count == 20 && result.items.allSatisfy(\.isOwned) && result.rejected.isEmpty)
    }
}

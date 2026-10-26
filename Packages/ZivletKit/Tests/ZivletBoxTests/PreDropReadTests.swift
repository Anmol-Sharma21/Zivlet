import AppKit
import TestSupport
import Testing
import ZivletCore
import ZivletShelfCore

@testable import ZivletBox

/// A thumbnail maker that fails the test when called: nothing is drawn from the dragged files before the drop.
@MainActor
struct FailingThumbnails: ThumbnailMaking {
    func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage? {
        Issue.record("a thumbnail was made before the drop")
        return nil
    }
}

/// A promise receiver that fails the test when it receives: promises are taken only inside the drop (D-M5b-5).
/// Asking whether there are promises reads the pasteboard's types only, so it is allowed.
@MainActor
struct FailingPromises: PromiseReceiving {
    func hasPromises(on pasteboard: NSPasteboard) -> Bool { false }

    func receivePromises(from pasteboard: NSPasteboard, into folder: URL) async -> PromiseOutcome {
        Issue.record("promises were received before the drop")
        return PromiseOutcome(received: [], failed: 0)
    }
}

/// D-M5b-4 as a test: while a drag is in flight the box reads the drag's types and item count, nothing else. No
/// bookmark, identity, size, thumbnail or promise before `performDragOperation` (the C4 question of P2-197).
@Suite("Pre-drop reads stay on the pasteboard (C4, D-M5b-4)")
@MainActor
struct PreDropReadTests {
    /// A controller whose bookmark, thumbnail and promise ports fail the test if anything calls them.
    static func failingController(_ rig: BoxRig) -> BoxController {
        BoxController(
            ports: BoxPorts(
                store: rig.store, storage: rig.storage, maker: FailingBookmarks(), resolver: rig.bookmarks,
                isMounted: { _ in true }, promises: FailingPromises(), thumbnails: FailingThumbnails(),
                quickLook: rig.quickLook, visibleFrames: { [BoxRig.display] }, finish: { .solid }),
            actions: rig.actions)
    }

    static func files(_ rig: BoxRig, count: Int) throws -> [URL] {
        try (0..<count).map { try rig.dir.file("drag-\($0).png") }
    }

    @Test func theIntakesPreviewCountsItemsOnly() throws {
        let rig = try BoxRig()
        let board = TestPasteboard(urls: try Self.files(rig, count: 3))
        let intake = BoxIntake(maker: FailingBookmarks(), storage: rig.storage, promises: FailingPromises())
        #expect(intake.preview(board.board) == 3)
    }

    @Test func aDragOverTheOpenPanelReadsNoFile() throws {
        let rig = try BoxRig()
        let box = Self.failingController(rig)
        box.start()
        box.showPanel(.saved)
        let board = TestPasteboard(urls: try Self.files(rig, count: 3))
        let info = FakeDraggingInfo(pasteboard: board.board)
        #expect(box.dropView.draggingEntered(info) == .copy)
        #expect(box.presentation.overlay == .dropTarget(count: 3))
        #expect(box.dropView.draggingUpdated(info) == .copy)
        box.dropView.draggingExited(info)
        #expect(box.presentation.overlay == nil)
        box.hidePanel()
    }

    @Test func aDragOverTheHiddenPanelIsRefusedWithoutReading() throws {
        let rig = try BoxRig()
        let box = Self.failingController(rig)
        box.start()
        let board = TestPasteboard(urls: try Self.files(rig, count: 2))
        let info = FakeDraggingInfo(pasteboard: board.board)
        #expect(box.dropView.prepareForDragOperation(info) == false)
        #expect(box.dropView.performDragOperation(info) == false)
    }
}

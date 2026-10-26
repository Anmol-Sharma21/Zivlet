import AppKit
import TestSupport
import Testing
import ZivletShelfCore

@testable import ZivletBox

/// The controller's thumbnails (19c D-BL11): asked for by the cells on screen, kept only in the cache, and drawn
/// once per turn however many arrive.
@Suite("Box thumbnails from the cells on screen (D-M5b-14)")
@MainActor
struct BoxThumbnailTests {
    static func shownBox(_ rig: BoxRig, files: Int) async throws -> BoxController {
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(files), newBox: false)
        box.showPanel()
        return box
    }

    @Test func manyArrivalsInOneTurnDrawOnce() async throws {
        let rig = try BoxRig()
        let maker = GatedThumbnailMaker()
        rig.thumbnailMaker = maker
        let box = try await Self.shownBox(rig, files: 3)
        let ids = box.viewModel.items.map(\.id)
        for id in ids { box.press(.shown(id, true)) }
        await settle()
        #expect(maker.requests.count == 3)
        let before = box.renders
        for url in maker.requests { maker.finish(url) }
        await settle()
        #expect(box.renders == before + 1)
        #expect(ids.allSatisfy { box.rendered?.images[$0]?.size.width == BoxLook.Grid.thumb })
        box.hidePanel()
    }

    @Test func aCellThatLeavesIsCancelledAndAskedAgainWhenItComesBack() async throws {
        let rig = try BoxRig()
        let maker = GatedThumbnailMaker()
        rig.thumbnailMaker = maker
        let box = try await Self.shownBox(rig, files: 1)
        let id = try #require(box.viewModel.items.first?.id)
        box.press(.shown(id, true))
        await settle()
        box.press(.shown(id, false))
        await settle()
        #expect(maker.cancelled == 1)
        box.press(.shown(id, true))
        await settle()
        #expect(maker.requests.count == 2)
        box.hidePanel()
    }

    @Test func hidingThePanelCancelsItsRequests() async throws {
        let rig = try BoxRig()
        let maker = GatedThumbnailMaker()
        rig.thumbnailMaker = maker
        let box = try await Self.shownBox(rig, files: 1)
        box.press(.shown(try #require(box.viewModel.items.first?.id), true))
        await settle()
        box.hidePanel()
        await settle()
        #expect(maker.cancelled == 1)
    }

    @Test func aNewlyDroppedItemCanBeDraggedOutAtOnce() async throws {
        let rig = try BoxRig()
        let box = try await Self.shownBox(rig, files: 1)
        _ = await box.add(try rig.files(1, prefix: "new"), newBox: false)
        #expect(box.viewModel.items.map { $0.url?.lastPathComponent } == ["f0.txt", "new0.txt"])
        box.hidePanel()
    }

    @Test func aShownPanelTakesANewFinishAtOnce() async throws {
        let rig = try BoxRig()
        let box = try await Self.shownBox(rig, files: 1)
        #expect(box.rendered?.finish == .solid)
        rig.finish = .contrast
        box.displayOptionsChanged()
        #expect(box.rendered?.finish == .contrast)
        box.hidePanel()
    }
}

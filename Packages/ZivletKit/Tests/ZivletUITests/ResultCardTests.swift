import AppKit
import SwiftUI
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Result card model (P1-41)")
struct ResultCardModelTests {
    @Test func successOffersUndoRevealOpenCopyAndShowsSizes() throws {
        let model = ResultCardModel(try HUDFx.finished(outputs: [("photo.png", before: 2_100_000, after: 640_000)]))
        #expect(model.buttons == [.undo, .reveal, .open, .copy])
        #expect(model.sizeLine == "photo.png · 2.1 MB → 640 KB")
        #expect(model.lingers == .seconds(4) && model.holdsWhileHovered)
        #expect(model.title == "Saved photo.png" && model.outputs.map(\.lastPathComponent) == ["photo.png"])
    }

    @Test func severalOutputsShowTheTotals() throws {
        let model = ResultCardModel(
            try HUDFx.finished(outputs: [
                ("a.png", before: 1_000_000, after: 500_000), ("b.png", before: 2_000_000, after: 500_000),
            ]))
        #expect(model.sizeLine == "2 files · 3 MB → 1 MB")
    }

    @Test func aCancelledBatchOnlyCloses() throws {
        let request = try HUDFx.request("a.heic")
        let batch = BatchID()
        let snapshot = BatchSnapshot(batch: batch, target: .png, plan: RequestPlan(requests: [request], rejections: []))
            .applying(.changed(batch, request.id, .cancelled)).applying(.finished(batch))
        let model = ResultCardModel(snapshot)
        #expect(model.buttons == [.close] && model.sizeLine == nil && model.title == "Cancelled")
    }

    @Test func hoverHoldsAndLeavingRestartsTheTimer() {
        var timer = LingerTimer(duration: .seconds(4))
        #expect(!timer.expired(at: .seconds(100)))  // not started
        timer = timer.started(at: .seconds(0)).hovered(at: .seconds(3))
        #expect(!timer.expired(at: .seconds(10)) && timer.deadline == nil)
        #expect(timer.unhovered(at: .seconds(10)).expired(at: .seconds(14)))
        #expect(!timer.unhovered(at: .seconds(10)).expired(at: .seconds(13)))
        #expect(LingerTimer(duration: .seconds(4)).started(at: .seconds(1)).deadline == .seconds(5))
    }
}

@Suite("Result card renders (P1-41)")
@MainActor
struct ResultCardSnapshotTests {
    @Test func theSuccessCardRendersWithItsButtons() throws {
        let snapshot = try HUDFx.finished(outputs: [("photo.png", before: 2_100_000, after: 640_000)])
        let card = ResultCard(model: ResultCardModel(snapshot), state: CardState(), act: { _ in })
        let image = try #require(ImageRenderer(content: card).nsImage)
        #expect(image.size.width == HUDLayout.size.width && image.size.height >= HUDLayout.size.height)
    }

    @Test func theHUDRendersAFinishedBatchAsACard() throws {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        let snapshot = try HUDFx.finished(outputs: [("photo.png", before: 2_100_000, after: 640_000)])
        hud.show(snapshot)
        #expect(hud.isVisible)
        hud.close(snapshot.batch)
    }
}

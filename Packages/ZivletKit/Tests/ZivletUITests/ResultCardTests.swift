import AppKit
import SwiftUI
import TestSupport
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

    @Test func failureOffersDetailsAndRetryAndStays() throws {
        let model = ResultCardModel(try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom")))
        #expect(model.buttons == [.showDetails, .retry, .close])
        #expect(model.lingers == nil)
        #expect(model.details == "Exit status 1.\nboom")
        #expect(model.title == "The conversion failed.")
    }

    @Test func aFailureWithoutDetailsStillOffersRetry() throws {
        let model = ResultCardModel(try HUDFx.failed(error: .diskFull))
        #expect(model.buttons == [.retry, .close] && model.details == nil)
    }

    @Test func aPartialBatchOffersBothSides() throws {
        let saved = try HUDFx.request("a.heic")
        let failed = try HUDFx.request("b.heic")
        let batch = BatchID()
        let output = PublishedOutput(
            url: URL(filePath: "/tmp/a.png"), format: .png, byteCount: 10, fileID: 1, modified: .distantPast)
        let snapshot = BatchSnapshot(
            batch: batch, target: .png, plan: RequestPlan(requests: [saved, failed], rejections: [])
        )
        .applying(.changed(batch, saved.id, .succeeded(output)))
        .applying(.changed(batch, failed.id, .failed(.processFailed(status: 2, stderrTail: "x"))))
        .applying(.finished(batch))
        let model = ResultCardModel(snapshot)
        #expect(model.buttons == [.undo, .reveal, .showDetails, .retry, .close] && model.lingers == nil)
    }

    @Test func downloadsFallbackIsAnnounced() throws {
        let model = ResultCardModel(
            try HUDFx.finished(outputs: [("a.png", before: 1, after: 1)], usedFallbackFolder: true))
        #expect(model.notes.contains("Saved to Downloads because the original folder is read-only."))
        let beside = ResultCardModel(try HUDFx.finished(outputs: [("a.png", before: 1, after: 1)]))
        #expect(beside.notes.isEmpty)
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

    @Test func theFailureCardRendersItsDetailsWhenAsked() throws {
        let model = ResultCardModel(try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom")))
        let state = CardState()
        state.showsDetails = true
        let image = try #require(ImageRenderer(content: ResultCard(model: model, state: state, act: { _ in })).nsImage)
        #expect(image.size.height > HUDLayout.size.height)
    }

    @Test func retryClosesTheFailedCardAndAsksForANewBatch() throws {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        var retried: [BatchID] = []
        hud.onRetry = { retried.append($0) }
        let snapshot = try HUDFx.failed(error: .stalled)
        hud.show(snapshot)
        hud.press(.retry, on: snapshot.batch)
        #expect(retried == [snapshot.batch] && !hud.isVisible)
    }

    @Test func theHUDRendersAFinishedBatchAsACard() throws {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        let snapshot = try HUDFx.finished(outputs: [("photo.png", before: 2_100_000, after: 640_000)])
        hud.show(snapshot)
        #expect(hud.isVisible)
        hud.close(snapshot.batch)
    }
}

#if DEBUG
    @Suite("UI test fixture (D-M4-14)")
    struct UITestFixtureTests {
        @Test func theFlagNamesAnAbsoluteDirectory() {
            #expect(UITestFixture.directory(arguments: ["Z", "-UITestFixture", "/tmp/x"])?.path == "/tmp/x")
            #expect(UITestFixture.directory(arguments: ["Z", "-UITestFixture", "relative"]) == nil)
            #expect(UITestFixture.directory(arguments: ["Z", "-UITestFixture"]) == nil)
        }

        @Test func theFixtureIsASuccessCard() throws {
            let dir = try TempDir()
            let model = ResultCardModel(try UITestFixture.snapshot(in: dir.url))
            #expect(model.title == "Saved practice.png" && model.buttons == [.undo, .reveal, .open, .copy])
            #expect(model.sizeLine?.hasPrefix("practice.png · 2.1 MB → ") == true)
        }
    }
#endif

@Suite("Result card undo (P1-41)")
@MainActor
struct ResultCardUndoTests {
    static let screens = { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] }

    static func trashed(_ snapshot: BatchSnapshot) -> UndoReply {
        UndoReply(message: "Moved 1 file to the Trash.", canRetry: false, removed: snapshot.outputs.map(\.url))
    }

    @Test func undoIsAskedOnceWhileItsReplyIsPending() async throws {
        let hud = ResultHUD(screens: Self.screens)
        let snapshot = try HUDFx.finished(outputs: [("photo.png", before: 2_000, after: 1_000)])
        var asked = 0
        hud.onUndo = { _ in
            asked += 1
            try? await Task.sleep(for: .milliseconds(30))
            return Self.trashed(snapshot)
        }
        hud.show(snapshot)
        hud.press(.undo, on: snapshot.batch)
        hud.press(.undo, on: snapshot.batch)
        #expect(hud.visibleButtons(snapshot.batch) == [.reveal, .open, .copy])
        await hud.pendingUndo(snapshot.batch)?.value
        #expect(asked == 1 && hud.card(snapshot.batch)?.undoMessage == "Moved 1 file to the Trash.")
        hud.close(snapshot.batch)
    }

    /// The outputs are in the Trash: nothing on the card may act on them, and the card leaves on its own again.
    @Test func afterAnUndoTheTrashedOutputsAreNotOfferedAndTheCardLeaves() async throws {
        let hud = ResultHUD(screens: Self.screens)
        let snapshot = try HUDFx.finished(outputs: [("photo.png", before: 2_000, after: 1_000)])
        hud.onUndo = { _ in Self.trashed(snapshot) }
        hud.show(snapshot)
        hud.press(.undo, on: snapshot.batch)
        #expect(!hud.isLingering(snapshot.batch))
        await hud.pendingUndo(snapshot.batch)?.value
        #expect(hud.visibleButtons(snapshot.batch).isEmpty)
        #expect(hud.isLingering(snapshot.batch))
        hud.close(snapshot.batch)
    }

    @Test func copyAfterAPartialUndoOffersOnlyWhatIsLeft() async throws {
        let hud = ResultHUD(screens: Self.screens)
        let snapshot = try HUDFx.finished(outputs: [("a.png", before: 2, after: 1), ("b.png", before: 2, after: 1)])
        let (first, second) = (snapshot.outputs[0].url, snapshot.outputs[1].url)
        hud.onUndo = { _ in
            UndoReply(message: "1 file could not be moved to the Trash.", canRetry: true, removed: [first])
        }
        var copied: [[URL]] = []
        hud.onCopy = { copied.append($0) }
        hud.show(snapshot)
        hud.press(.undo, on: snapshot.batch)
        await hud.pendingUndo(snapshot.batch)?.value
        hud.press(.copy, on: snapshot.batch)
        #expect(copied == [[second]])
        #expect(hud.visibleButtons(snapshot.batch) == [.undo, .reveal, .open, .copy])
        hud.close(snapshot.batch)
    }

    @Test func anUndoThatChangedNothingKeepsTheButtons() async throws {
        let hud = ResultHUD(screens: Self.screens)
        let snapshot = try HUDFx.finished(outputs: [("photo.png", before: 2_000, after: 1_000)])
        hud.onUndo = { _ in UndoReply(message: "This can no longer be undone.", canRetry: false) }
        hud.show(snapshot)
        hud.press(.undo, on: snapshot.batch)
        await hud.pendingUndo(snapshot.batch)?.value
        #expect(hud.visibleButtons(snapshot.batch) == [.reveal, .open, .copy] && hud.isLingering(snapshot.batch))
        hud.close(snapshot.batch)
    }
}

import AppKit
import SwiftUI
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Island cards: two styles, symbols, fewer rows (19b §5)")
@MainActor
struct NotchCardLayoutTests {
    @Test func theWorkingCardIsTwoRows() throws {
        let card = NotchWorkingCard(snapshot: try HUDFx.running(JobProgress(fraction: 0.4, eta: .seconds(40)))) {}
        let size = try #require(ImageRenderer(content: card.frame(width: NotchCard.contentWidth)).nsImage).size
        #expect(size.height <= NotchLook.Card.workingHeight)
    }

    @Test func theFirstRowSaysNameAndTarget() throws {
        #expect(NotchWorkingCard.title(for: try HUDFx.running(JobProgress(fraction: 0.4))) == "clip.mov → MP4")
        #expect(NotchWorkingCard.percent(try HUDFx.running(JobProgress(fraction: 0.405))) == "40%")
    }

    @Test func theSecondRowHasTheShortTimeLeftAndTheBatchPosition() throws {
        let running = try HUDFx.running(JobProgress(fraction: 0.4, eta: .seconds(190)))
        #expect(NotchWorkingCard.details(running) == ["3 min"])
        #expect(NotchWorkingCard.details(try HUDFx.snapshot(submitted: 3)) == ["1 of 3"])
        let unknown = try HUDFx.running(JobProgress(fraction: nil, bytesWritten: 12_400_000))
        #expect(NotchWorkingCard.details(unknown) == ["12.4 MB written"] && NotchWorkingCard.percent(unknown) == nil)
    }

    @Test func cancelIsTheCardsOnlyPress() { #expect(NotchWorkingCard.presses == [.cancel]) }

    @Test func theCardSitsInsideTheBodyOnTheGrid() {
        #expect(NotchCard.sideInset == NotchLook.Spacing.l && NotchCard.topInset == NotchLook.Spacing.s)
        #expect(NotchCard.bottomInset == NotchLook.Spacing.m)
        #expect(NotchCard.contentWidth == 380 - 2 * 6 - 2 * 16)
    }

    // MARK: Result card (D14)

    private func saved() throws -> ResultCardModel {
        ResultCardModel(try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg))
    }

    @Test func theResultCardNamesTheFileOnce() throws {
        let lines = NotchResultCard.lines(try saved())
        #expect(lines.primary == "Saved photo.jpg" && lines.secondary == "2.1 MB → 640 KB")
    }

    @Test func theButtonsAreTheModelsInItsOrder() throws {
        let state = CardState()
        #expect(NotchResultCard.presses(try saved(), state: state) == [.undo, .reveal, .open, .copy])
        state.undoInFlight = true
        #expect(NotchResultCard.presses(try saved(), state: state) == [.reveal, .open, .copy])
    }

    @Test func theThumbnailIs40PointsWithTheInnerRadius() {
        #expect(NotchResultCard.thumbnailSide == 40 && NotchResultCard.thumbnailRadius == 8)
    }

    @Test func theUndoReplyIsACaptionAndTheCardGrows() throws {
        let model = try saved()
        let state = CardState()
        let before = try #require(ImageRenderer(content: card(model, state)).nsImage).size.height
        state.undoMessage = "Moved photo.jpg to the Trash."
        let after = try #require(ImageRenderer(content: card(model, state)).nsImage).size.height
        #expect(after > before)
    }

    private func card(_ model: ResultCardModel, _ state: CardState) -> some View {
        NotchResultCard(model: model, state: state, width: NotchCard.contentWidth) { _ in }
    }
}

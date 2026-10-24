import AppKit
import SwiftUI
import Testing
import ZivletActions
import ZivletCore
import ZivletNotch
import ZivletRuntime

@testable import ZivletUI

@Suite("Island cards: two styles, symbols, fewer rows (19b §5)")
@MainActor
struct NotchCardLayoutTests {
    @Test func theWorkingCardIsTwoRows() throws {
        let card = NotchWorkingCard(snapshot: try HUDFx.running(JobProgress(fraction: 0.4, eta: .seconds(40)))) {}
        let size = try #require(
            ImageRenderer(content: card.frame(width: NotchCard.contentWidth(underHousing: true))).nsImage
        ).size
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

    /// 19b §3.1: the tab's ends sit 8 pt in under a housing, 12 pt in from the pill's round ends.
    @Test func thePillsTabKeepsItsGlyphsClearOfTheRoundEnds() {
        #expect(NotchTab.sideInset(underHousing: true) == NotchLook.Spacing.s)
        #expect(NotchTab.sideInset(underHousing: false) == NotchLook.Spacing.m)
    }

    @Test func cancelIsTheCardsOnlyPress() { #expect(NotchWorkingCard.presses == [.cancel]) }

    @Test func theCardSitsInsideTheBodyOnTheGrid() {
        #expect(NotchCard.sideInset == NotchLook.Spacing.l)
        #expect(NotchCard.topInset(underHousing: true) == NotchLook.Spacing.s)  // the housing's black is above it
        #expect(NotchCard.topInset(underHousing: false) == NotchLook.Spacing.m)  // the pill: as far as the bottom
        #expect(NotchCard.bottomInset == NotchLook.Spacing.m)
        #expect(NotchCard.contentWidth(underHousing: true) == CGFloat(380 - 2 * 6 - 2 * 16))
        #expect(NotchCard.contentWidth(underHousing: false) == CGFloat(380 - 2 * 16))  // the pill has no flare
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

    @Test func theThumbnailIsConcentricWithTheCard() {
        #expect(Double(NotchResultCard.thumbnailRadius) == IslandLook.Radius.inner)
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
        NotchResultCard(model: model, state: state, width: NotchCard.contentWidth(underHousing: true)) { _ in }
    }

    // MARK: Failure and action cards (D15)

    @Test func theFailureCardLeadsWithTheReason() throws {
        let failed = try HUDFx.failed(error: .diskFull)
        let lines = NotchFailureCard.lines(ResultCardModel(failed))
        let shown = BatchPresentation.make(failed)
        #expect(lines.primary == shown.title && lines.secondary == shown.subtitle)
    }

    @Test func theFailureCardsButtonsSitBesideItsLines() throws {  // seen on screen: a row of its own left a gap
        let model = ResultCardModel(try HUDFx.failed(error: .diskFull))
        let card = NotchFailureCard(model: model, state: CardState(), width: NotchCard.contentWidth(underHousing: true))
        { _ in }
        let size = try #require(ImageRenderer(content: card).nsImage).size
        #expect(size.height <= NotchLook.Card.failureHeight)
    }

    @Test func aReasonThatFitsBesideTheButtonsStaysOnOneLine() throws {  // seen on screen: it wrapped at half width
        let model = ResultCardModel(try HUDFx.failed(error: .diskFull))
        let card = NotchFailureCard(model: model, state: CardState(), width: NotchCard.contentWidth(underHousing: true))
        { _ in }
        let size = try #require(ImageRenderer(content: card).nsImage).size
        #expect(size.height <= 40)  // one line of reason, one of name
    }

    @Test func detailsShowOnceWithAChevronAndKeepTheirTitle() throws {
        let model = ResultCardModel(try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom")))
        let state = CardState()
        #expect(NotchFailureCard.presses(model, state: state) == [.showDetails, .retry, .close])
        #expect(NotchIconButton.symbol(.showDetails) == "chevron.down")
        #expect(NotchIconButton.title(.showDetails) == "Show Details")
        state.showsDetails = true
        #expect(NotchFailureCard.presses(model, state: state) == [.retry, .close])
    }

    @Test func closeIsTheCancelActionAndNothingElseIs() {
        #expect(NotchButtonRow.shortcut(.close) == .cancelAction)
        #expect(NotchHUD.Press.allCases.filter { NotchButtonRow.shortcut($0) != nil } == [.close])
    }

    @Test func theActionCardShowsFiveLinesThenACount() {
        let card = ActionCard(title: "2 files were skipped", lines: (1...7).map { "file\($0).txt" })
        let lines = NotchActionCard.lines(.partial(toast: "Copied 5 files", card: card, undo: nil))
        #expect(lines.count == 6 && lines.last == "and 2 more" && lines.first == "file1.txt")
    }

    @Test func theActionCardOffersCloseAndDetailsLikeM5a() {
        let model = ActionHUDModel()
        model.present(.failed(ActionCard(title: "Could not copy", detail: "Permission denied")))
        #expect(NotchActionCard.presses(model) == [.showDetails, .close])
        #expect(NotchActionCard.title(.failed(ActionCard(title: "Could not copy"))) == "Could not copy")
    }
}

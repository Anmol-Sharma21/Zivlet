import Foundation
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

/// A batch whose jobs were all cancelled finishes with nothing saved and nothing failed (BatchPresentation's
/// `.cancelled`): the island says so with a neutral glyph and offers only Close, never the failure's triangle or
/// the saved check mark.
@Suite("A cancelled batch on the island")
struct NotchCancelledTests {
    @Test func theCardForACancelledBatchIsNeitherAFailureNorAResult() throws {
        #expect(NotchCard.face(try HUDFx.cancelled(count: 2)) == .cancelled)
        #expect(NotchCard.face(try HUDFx.failed(error: .diskFull)) == .failure)
        #expect(NotchCard.face(try HUDFx.finished(outputs: [("a.png", before: 1, after: 1)])) == .result)
        #expect(NotchCard.face(try HUDFx.running(JobProgress(fraction: 0.4))) == .working)
    }

    @Test func theCancelledCardHasTheNeutralGlyphAndOnlyClose() throws {
        let model = ResultCardModel(try HUDFx.cancelled())
        #expect(model.phase == .cancelled && model.buttons == [.close])
        #expect(NotchFailureCard.glyph(model) == NotchSymbol.cancelled)
        #expect(NotchFailureCard.glyph(ResultCardModel(try HUDFx.failed(error: .diskFull))) == NotchSymbol.failed)
        #expect(NotchSymbol.cancelled != NotchSymbol.saved && NotchSymbol.cancelled != NotchSymbol.failed)
    }

    @Test func theToastOfACancelledBatchHasTheNeutralGlyph() throws {
        let board = NotchHUDBoard().updating(try HUDFx.cancelled(), display: 1, now: .seconds(1))
        #expect(board.toastGlyph(on: 1) == .cancelled)
        #expect(NotchSymbol.name(for: ToastGlyph.cancelled) == NotchSymbol.cancelled)
    }

    @Test func aCancelledListRowOffersCloseOnly() throws {
        let board = try [HUDFx.cancelled(), HUDFx.running(JobProgress(fraction: 0.4))]
            .reduce(NotchHUDBoard()) { $0.updating($1, display: 1, now: .seconds(1)) }
        let row = try #require(board.rows(on: 1).first { $0.status == .cancelled })
        #expect(NotchListRow.presses(row, offersUndo: false) == [.close])
    }

    /// Success comes from the phase, not from which buttons the model happens to carry.
    @Test func theResultCardSaysSavedOnlyForASucceededBatch() throws {
        let saved = ResultCardModel(try HUDFx.finished(outputs: [("photo.jpg", before: 2, after: 1)], target: .jpg))
        #expect(saved.phase == .succeeded && NotchResultCard.lines(saved).primary == "Saved photo.jpg")
    }
}

import CoreGraphics
import Testing
import ZivletActions
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Notch HUD: one-line text that gives way in the right place, and the card's inset")
struct NotchLineTests {
    @Test func theSavedToastsOneLineFormStaysForTheSpokenLabel() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
        let board = NotchHUDBoard().updating(done, display: 1, now: .seconds(1))
        #expect(board.toastLine(on: 1) == "Saved photo.jpg · 2.1 MB → 640 KB")
    }

    @Test func theFailureToastKeepsTheReasonAndDropsItsFullStopBeforeTheSeparator() throws {
        let failed = try HUDFx.failed(error: .diskFull)
        let parts = NotchHUDCopy.failureParts(failed)
        #expect(parts.first == LinePart(text: "There isn't enough free disk space", givesWay: false))
        #expect(parts.last?.givesWay == true && parts.last?.text.hasPrefix(" · ") == true)
        #expect(NotchHUDCopy.failure(failed) == parts.map(\.text).joined())
    }

    @Test func theSavedToastSplitsTheNameFromTheSizes() throws {  // 19b D-NL7, D-NL8
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
        let line = NotchHUDCopy.savedLine(done)
        #expect(line.primary == [LinePart(text: "Saved photo.jpg", givesWay: true)])
        #expect(line.secondary == "2.1 MB → 640 KB" && !line.secondaryGivesWay)
        let board = NotchHUDBoard().updating(done, display: 1, now: .seconds(1))
        #expect(board.toastStyledLine(on: 1) == line)
        #expect(board.toastAccessibilityLabel(on: 1) == "Saved photo.jpg, 2.1 MB to 640 KB")  // unchanged spoken form
    }

    @Test func theFailureToastKeepsTheWholeReasonAndTheNameGivesWay() throws {
        let failed = try HUDFx.failed(error: .diskFull)
        let line = NotchHUDCopy.failureLine(failed)
        #expect(line.primary == [LinePart(text: "There isn't enough free disk space", givesWay: false)])
        #expect(line.secondary == BatchPresentation.make(failed).subtitle && line.secondaryGivesWay)
    }

    @Test func aLongNameGivesWayAndTheSizesStay() throws {
        let name = String(repeating: "holiday-", count: 10) + ".jpg"
        let done = try HUDFx.finished(outputs: [(name, before: 2_100_000, after: 640_000)], target: .jpg)
        let line = NotchHUDCopy.savedLine(done)
        #expect(line.primary.allSatisfy(\.givesWay) && line.secondary == "2.1 MB → 640 KB")
    }

    @Test func anActionToastIsOneLine() throws {
        let board = NotchHUDBoard().updating(
            .done(toast: "Copied 1 file", undo: nil), display: 1, now: .seconds(1))
        #expect(
            board.toastStyledLine(on: 1) == NotchToastLine(primary: [LinePart(text: "Copied 1 file", givesWay: false)]))
    }

    @Test func theWorkingLineLetsTheNameGiveWayAndKeepsThePercent() throws {
        let running = try HUDFx.running(JobProgress(fraction: 0.4), name: "a-very-long-holiday-video.mov")
        let parts = HUDCopy.workingParts(running)
        #expect(parts.first == LinePart(text: "a-very-long-holiday-video.mov", givesWay: true))
        #expect(parts.last == LinePart(text: " · 40%", givesWay: false))
        #expect(HUDCopy.working(running) == parts.map(\.text).joined())
    }

    @Test func theExpandedCardHasTheGlassCardsContentWidthCentredInTheIsland() {
        #expect(NotchCard.contentWidth == HUDLayout.contentWidth)
        #expect(NotchCard.sideInset == 24)
    }
}

import CoreGraphics
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Notch HUD: one-line text that gives way in the right place, and the card's inset")
struct NotchLineTests {
    @Test func theSavedToastLetsTheNameGiveWayAndKeepsTheSizesWhole() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
        let board = NotchHUDBoard().updating(done, display: 1, now: .seconds(1))
        #expect(
            board.toastParts(on: 1) == [
                LinePart(text: "Saved photo.jpg", givesWay: true),
                LinePart(text: " · 2.1 MB → 640 KB", givesWay: false),
            ])
        #expect(board.toastLine(on: 1) == "Saved photo.jpg · 2.1 MB → 640 KB")
    }

    @Test func theFailureToastKeepsTheReasonAndDropsItsFullStopBeforeTheSeparator() throws {
        let failed = try HUDFx.failed(error: .diskFull)
        let parts = NotchHUDCopy.failureParts(failed)
        #expect(parts.first == LinePart(text: "There isn't enough free disk space", givesWay: false))
        #expect(parts.last?.givesWay == true && parts.last?.text.hasPrefix(" · ") == true)
        #expect(NotchHUDCopy.failure(failed) == parts.map(\.text).joined())
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

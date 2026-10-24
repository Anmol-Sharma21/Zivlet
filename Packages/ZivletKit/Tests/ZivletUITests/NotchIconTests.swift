import AppKit
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

@Suite("Island glyphs: the target's family in white symbols (19b D-NL10, F5, F6)")
struct NotchIconTests {
    @Test func aWorkingJobShowsItsTargetsFamily() throws {
        let board = NotchHUDBoard().updating(
            try HUDFx.running(JobProgress(fraction: 0.4)), display: 1, now: .seconds(1))  // clip.mov → MP4
        #expect(board.tab(on: 1)?.icon == .family(.video))
    }

    @Test func aFinishedImageShowsThePhotoSymbol() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
        #expect(NotchHUDBoard().updating(done, display: 1, now: .seconds(1)).tab(on: 1)?.icon == .family(.image))
    }

    @Test(arguments: FormatFamily.allCases)
    func everyFamilyHasASystemSymbol(family: FormatFamily) {
        #expect(NSImage(systemSymbolName: NotchSymbol.name(for: family), accessibilityDescription: nil) != nil)
    }

    @Test func theFamiliesAreTheDesigns() {
        let names = FormatFamily.allCases.map(NotchSymbol.name(for:))
        #expect(names == ["photo", "waveform", "film", "doc.text", "tablecells", "captions.bubble", "archivebox"])
    }

    @Test func aDoneActionShowsTheCheckMarkNotTheCopyGlyph() {
        #expect(NotchSymbol.name(for: ToastGlyph.action) == "checkmark.circle.fill")
    }

    @Test func theRingIsTheTokensSize() { #expect(NotchLook.Ring.side == 16 && NotchLook.Symbol.tabBox == 16) }
}

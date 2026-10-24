import AppKit
import SwiftUI
import Testing

@testable import ZivletUI

@Suite("Island icon buttons (19b D-NL9)")
@MainActor
struct NotchIconButtonTests {
    @Test(arguments: NotchHUD.Press.allCases)
    func everyPressHasASymbolAndTodaysTitle(press: NotchHUD.Press) {
        let symbol = NotchIconButton.symbol(press)
        #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        #expect(NotchIconButton.title(press) == NotchListRow.title(press))  // the M5a words, unchanged
    }

    @Test func theSymbolsAreTheDesignsAndTellThePressesApart() {
        #expect(NotchIconButton.symbol(.undo) == "arrow.uturn.backward")
        #expect(NotchIconButton.symbol(.reveal) == "folder" && NotchIconButton.symbol(.retry) == "arrow.clockwise")
        #expect(Set(NotchHUD.Press.allCases.map(NotchIconButton.symbol)).count == NotchHUD.Press.allCases.count)
    }

    @Test func theHitAreaIs28Points() throws {
        let image = try #require(ImageRenderer(content: NotchIconButton(press: .undo) {}).nsImage)
        #expect(image.size == CGSize(width: 28, height: 28))
    }

    /// The label and the tooltip are this title. SwiftUI builds no accessibility tree without an assistive client, so
    /// Voice Control finding the button is checked by hand (QA Q30).
    @Test func theLabelAndTooltipKeepTodaysWords() {
        let titles = NotchHUD.Press.allCases.map(NotchIconButton.title)
        #expect(titles == ["Undo", "Reveal", "Open", "Copy", "Show Details", "Retry", "Close", "Cancel"])
    }

    @Test func increaseContrastShowsTheBackgroundAtRest() {
        #expect(NotchIconButton.restingFill(increaseContrast: false) == 0)
        #expect(NotchIconButton.restingFill(increaseContrast: true) == 0.18)
        #expect(NotchIconButton.fill(pressed: false, hovered: true, increaseContrast: false) == 0.14)
        #expect(NotchIconButton.fill(pressed: true, hovered: true, increaseContrast: true) == 0.22)
    }
}

import AppKit
import SwiftUI
import Testing
import ZivletNotch

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

    /// Cancel stops a running conversion and Close only dismisses; they sit in the same column of the list, so they
    /// must not both be an X.
    @Test func cancelAndCloseAreDifferentShapes() {
        let cancel = NotchIconButton.symbol(.cancel)
        #expect(cancel == "stop.fill")
        #expect(!cancel.hasPrefix("xmark") && NotchIconButton.symbol(.close).hasPrefix("xmark"))
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

    /// The resting circle follows the island's own outline (its finish), the same source as the outline, so the
    /// forced screenshot finish and the real Increase Contrast setting draw the same buttons.
    @Test func theRestingCircleFollowsTheIslandsOutline() throws {
        #expect(try Self.edgeAlpha(outlined: false) == 0)
        #expect(try Self.edgeAlpha(outlined: true) > 0)
    }

    /// The alpha of a pixel inside the round hit area, left of the symbol.
    private static func edgeAlpha(outlined: Bool) throws -> UInt8 {
        let renderer = ImageRenderer(
            content: NotchIconButton(press: .undo) {}.environment(\.islandOutlined, outlined))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let context = try #require(
            CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        return pixels[(14 * image.width + 3) * 4 + 3]
    }

    @Test func buttonHoverIsInstantUnderReduceMotion() {
        #expect(NotchIconButton.hoverAnimation(reduceMotion: true) == nil)
        #expect(NotchIconButton.hoverAnimation(reduceMotion: false) == .easeOut(duration: 0.12))
    }
}

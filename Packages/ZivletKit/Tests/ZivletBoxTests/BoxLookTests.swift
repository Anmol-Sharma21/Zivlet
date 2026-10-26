import AppKit
import Testing
import ZivletNotch
import ZivletNotchCore

@testable import ZivletBox

@Suite("Drop Box tokens (19c §3)")
struct BoxLookTests {
    private let worst = IslandLook.worstGlassLuminance
    private var solid: Double { IslandInk.luminance(IslandLook.solidGrey) }

    @Test func cellNamesAreWhiteBecauseSmallTextNeedsTheMargin() {
        #expect(BoxLook.Grid.nameOpacity == 1)
        #expect(IslandInk.contrast(textOpacity: BoxLook.Grid.nameOpacity, over: worst) >= 6.0)
    }

    @Test func secondaryTextPassesOnTheWorstGlass() {
        #expect(IslandInk.contrast(textOpacity: IslandInk.secondaryOpacity, over: worst) >= 4.5)
    }

    @Test func theSolidFallbackPassesWithMargin() {
        #expect(IslandInk.contrast(textOpacity: 1, over: solid) >= 16)
        #expect(IslandInk.contrast(textOpacity: IslandInk.secondaryOpacity, over: solid) >= 11)
    }

    @Test func theBadgeReadsOverAWhiteThumbnail() {  // non-text, WCAG 1.4.11
        #expect(IslandInk.contrast(textOpacity: 1, overBlack: BoxLook.Badge.circleOpacity, over: 1) >= 4.6)
    }

    @Test func theEmptySymbolMeetsNonTextContrast() {
        #expect(IslandInk.contrast(textOpacity: BoxLook.Empty.symbolOpacity, over: worst) >= 3)
    }

    @Test func whiteOnTheTraysBandPasses() { #expect(IslandInk.contrast(textOpacity: 1) > 20) }

    @Test func theDefaultWidthHoldsFiveCells() {
        let expected = 2 * IslandContentLook.Spacing.l + 5 * BoxLook.Grid.cell + 4 * BoxLook.Grid.gap
        #expect(BoxLook.Panel.width == expected && BoxLook.Panel.width == 384)
        #expect(BoxLook.Grid.columns == 5)
    }

    @Test func theTokensSitOnTheFourPointGrid() {
        let values = [
            BoxLook.Panel.minHeight, BoxLook.Panel.headerHeight, BoxLook.Panel.barHeight, BoxLook.Panel.collapsedHeight,
            BoxLook.Grid.cell, BoxLook.Grid.thumb, BoxLook.Grid.gap, BoxLook.List.rowHeight, BoxLook.List.icon,
            BoxLook.Tab.width, BoxLook.Tab.height, BoxLook.Tab.dropWidth, BoxLook.Tray.thumb,
        ]
        for value in values { #expect(value.truncatingRemainder(dividingBy: 4) == 0) }
        #expect(BoxLook.Panel.radius == IslandLook.Radius.card)
    }

    @Test(arguments: BoxSymbols.all)
    func everySymbolExists(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }

    @Test func everySymbolOf19cIsListedOnce() {
        #expect(BoxSymbols.all.count == 25 && Set(BoxSymbols.all).count == 25)
    }
}

@Suite("Drop Box finish (19c D-BL1, D-BL2)")
struct BoxFinishTests {
    @Test(arguments: [
        (false, false, BoxFinish.glass), (true, false, .solid), (false, true, .contrast), (true, true, .contrast),
    ])
    func theFinishFollowsTheDisplayOptions(reduceTransparency: Bool, increaseContrast: Bool, expected: BoxFinish) {
        let settings = IslandFinish.Settings(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
        #expect(BoxFinish.resolve(settings) == expected)
    }

    @Test func eachFinishDrawsAsTheIslandsFloatingFinish() {
        #expect(BoxFinish.glass.islandFinish == .glass(band: 0))
        #expect(BoxFinish.solid.islandFinish == .solid(band: 0, outline: false))
        #expect(BoxFinish.contrast.islandFinish == .solid(band: 0, outline: true))
    }
}

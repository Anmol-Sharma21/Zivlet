import Foundation
import Testing
import ZivletCore

@testable import ZivletWheelCore

@Suite("Wheel model reducer and selection (P0-27, 03a §2.4–2.6)")
struct WheelModelTests {
    let builder = SliceBuilder()
    var png: WheelModel {
        WheelModel(
            mode: .convert, content: builder.content(for: .convert, items: [SelectionItem(.png)]),
            idleHubLabel: "photo.png\n2.2 MB")
    }

    @Test func pointerOnASlotHighlightsItAndTheHubShowsItsLabel() {
        let hot = png.applying(.slot(2))
        #expect(hot.highlighted == 2)
        #expect(hot.hubLabel == "HEIC")
        #expect(hot.dropTarget == .convert(.heic))
    }

    @Test func hubAndOutsideClearTheHighlightAndRestoreTheIdleLabel() {
        let hot = png.applying(.slot(0))
        #expect(hot.applying(.hub).highlighted == nil)
        #expect(hot.applying(.outside).hubLabel == "photo.png\n2.2 MB")
        #expect(hot.applying(.hub).dropTarget == nil)
    }

    @Test func unchangedHitReturnsAnEqualValue() {
        let hot = png.applying(.slot(1))
        #expect(hot.applying(.slot(1)) == hot)
    }

    @Test func outOfRangeSlotAndEmptyWheelNeverHighlight() {
        #expect(png.applying(.slot(99)).highlighted == nil)
        let empty = WheelModel(mode: .tools, content: .empty(.noTools(.srt)), idleHubLabel: "x")
        #expect(empty.applying(.slot(0)).highlighted == nil)
        #expect(empty.dropTarget == nil)
    }

    @Test func switchingModeClearsTheHighlightAndKeepsTheHubLabel() {
        let hot = png.applying(.slot(0))
        let tools = hot.switching(to: .tools, content: builder.content(for: .tools, items: [SelectionItem(.png)]))
        #expect(tools.mode == .tools && tools.highlighted == nil)
        #expect(tools.idleHubLabel == "photo.png\n2.2 MB")
        #expect(tools.slices.first?.target == .tool(.copyText))
    }

    @Test func hubCompactStyleSurvivesHighlightAndModeSwitch() {
        let several = WheelModel(
            mode: .convert, content: builder.content(for: .convert, items: [SelectionItem(.png)]),
            idleHubLabel: "2 FOLDERS", hubIsCompact: true)
        #expect(!png.hubIsCompact)
        #expect(several.applying(.slot(1)).hubIsCompact)
        #expect(several.switching(to: .actions, content: builder.content(for: .actions, items: [])).hubIsCompact)
    }

    @Test func hitUsesTheCurrentHighlightForHysteresis() {
        // Seven slots: span ≈ 51.4°. Just past the 0|1 boundary, 2° in: still slot 0 while it is current.
        let span = 2 * Double.pi / 7
        let angle = Double.pi / 2 - (span / 2 + 2 * .pi / 180)
        let p = Point2D(x: 90 * cos(angle), y: 90 * sin(angle))
        #expect(png.hit(p) == .slot(1))
        #expect(png.applying(.slot(0)).hit(p) == .slot(0))
    }

    @Test func dropBuildsATypedSelection() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        let selection = try #require(png.applying(.slot(0)).selection(urls: urls))
        #expect(selection == WheelSelection(mode: .convert, target: .convert(.jpg), urls: urls))
        #expect(selection.summary() == "Convert → JPG · 2 items")
        #expect(png.selection(urls: urls) == nil)
        #expect(png.applying(.slot(0)).selection(urls: []) == nil)
    }

    @Test func selectionSummariesNameToolsAndActions() {
        let one = [URL(fileURLWithPath: "/tmp/clip.mov")]
        #expect(WheelSelection(mode: .tools, target: .tool(.videoTrim), urls: one).summary() == "Tools → TRIM · 1 item")
        #expect(
            WheelSelection(mode: .actions, target: .action(.copyFilePath), urls: one).summary()
                == "Actions → COPY PATH · 1 item")
    }

    @Test func selectionRoundTripsThroughJSON() throws {
        let selection = WheelSelection(
            mode: .tools, target: .tool(.shrink), urls: [URL(fileURLWithPath: "/tmp/a b.png")])
        let data = try JSONEncoder().encode(selection)
        #expect(try JSONDecoder().decode(WheelSelection.self, from: data) == selection)
    }

    @Test func slicesCanBeBuiltDirectlyForShellTests() {
        let slice = WheelSlice(id: "convert.png", label: "PNG", symbolName: nil, target: .convert(.png), badge: nil)
        let model = WheelModel(mode: .convert, content: .slices([slice]), idleHubLabel: "x", highlighted: 0)
        #expect(model.highlightedSlice == slice)
        #expect(
            WheelModel(mode: .convert, content: .slices([slice]), idleHubLabel: "x", highlighted: 3).highlighted == nil)
    }
}

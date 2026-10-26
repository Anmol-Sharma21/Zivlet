import AppKit
import SwiftUI
import Testing
import ZivletShelfCore

@testable import ZivletBox

@Suite("Box layout on the solid finish (19c §3, §4.1)")
@MainActor
struct BoxLayoutTests {
    private func rendered(_ model: BoxViewModel) throws -> NSSize {
        let renderer = ImageRenderer(content: BoxPanelView(model: model, press: { _ in }))
        renderer.scale = 1
        return try #require(renderer.nsImage).size
    }

    @Test func theExpandedPanelIsThePanelWidth() throws {
        let model = BoxViewFixtures.model(BoxViewFixtures.items(3))
        let size = try rendered(model)
        #expect(size.width == BoxLook.Panel.width)
        #expect(size.height == BoxLayout.size(of: model).height)
    }

    @Test func theGridWrapsAtFive() {
        #expect(BoxLayout.gridRows(5) == 1 && BoxLayout.gridRows(6) == 2 && BoxLayout.gridRows(0) == 0)
        let five = BoxLayout.size(of: BoxViewFixtures.model(BoxViewFixtures.items(5))).height
        let six = BoxLayout.size(of: BoxViewFixtures.model(BoxViewFixtures.items(6))).height
        #expect(six - five == BoxLook.Grid.rowHeight + BoxLook.Grid.gap)
    }

    @Test func theListRowIs36Points() {
        let one = BoxLayout.size(of: BoxViewFixtures.model(BoxViewFixtures.items(4), mode: .list)).height
        let two = BoxLayout.size(of: BoxViewFixtures.model(BoxViewFixtures.items(5), mode: .list)).height
        #expect(two - one == 36 && BoxLook.List.rowHeight == 36)
    }

    @Test func theCollapsedCardIs88PointsHigh() throws {
        let model = BoxViewFixtures.model(BoxViewFixtures.items(12), base: .collapsed)
        #expect(try rendered(model) == NSSize(width: BoxLook.Panel.width, height: 88))
    }

    @Test func theDockedTabWidensDuringADrag() throws {
        let tab = BoxViewFixtures.model(BoxViewFixtures.items(2), base: .docked(.right))
        #expect(try rendered(tab) == NSSize(width: 28, height: 64))
        let target = BoxViewFixtures.model(
            BoxViewFixtures.items(2), base: .docked(.right), overlay: .dropTarget(count: 1))
        #expect(BoxLayout.size(of: target) == CGSize(width: 48, height: 64))
    }

    @Test func thePanelStopsGrowingAtItsMaximum() {
        let model = BoxViewFixtures.model(BoxViewFixtures.items(200))
        #expect(BoxLayout.size(of: model).height == 678 && BoxLayout.scrolls(model))
        #expect(!BoxLayout.scrolls(BoxViewFixtures.model(BoxViewFixtures.items(3))))
    }

    @Test func anEmptyBoxKeepsTheMinimumHeight() throws {
        let model = BoxViewFixtures.model([])
        #expect(BoxLayout.size(of: model).height == BoxLook.Panel.minHeight)
        #expect(try rendered(model).width == BoxLook.Panel.width)
    }

    @Test func aHiddenBoxHasNoSize() { #expect(BoxLayout.size(of: BoxViewFixtures.model([], base: .hidden)) == .zero) }

    @Test func namesGiveWayInTheMiddle() {
        #expect(BoxCell.nameTruncation == .middle && BoxRow.nameTruncation == .middle)
    }

    @Test(arguments: [
        BoxPresentation.Overlay.dropTarget(count: 3), .busy(verb: "Moving 3 items", fraction: 0.4),
        .confirm(.trash(count: 3)), .confirm(.clear),
    ])
    func everyOverlayDrawsAtThePanelWidth(_ overlay: BoxPresentation.Overlay) throws {
        let model = BoxViewFixtures.model(BoxViewFixtures.items(7, missing: 2), overlay: overlay)
        #expect(try rendered(model).width == BoxLook.Panel.width)
    }

    @Test func listSelectionAndGlassAlsoDraw() throws {
        let items = BoxViewFixtures.items(4, missing: 1)
        let list = BoxViewFixtures.model(items, mode: .list, selection: [items[1].id], finish: .contrast)
        #expect(try rendered(list).width == BoxLook.Panel.width)
        let glass = BoxViewFixtures.model(items, selection: [items[0].id], finish: .glass)
        #expect(try rendered(glass).width == BoxLook.Panel.width)
    }

    @Test func theCompactViewIsTheTraysWidth() throws {
        let model = BoxViewFixtures.model(BoxViewFixtures.items(9, missing: 1))
        let renderer = ImageRenderer(content: BoxCompactView(model: model, press: { _ in }))
        renderer.scale = 1
        #expect(try #require(renderer.nsImage).size.width == BoxLook.Tray.compactWidth)
        #expect(BoxCompactView.strip(model.items).count == BoxLook.Tray.maxThumbs - 1)
        #expect(BoxCompactView.overflow(model.items.count) == 4 && BoxCompactView.overflow(6) == 0)
        #expect(BoxCompactView.strip(Array(model.items.prefix(6))).count == 6)
    }
}

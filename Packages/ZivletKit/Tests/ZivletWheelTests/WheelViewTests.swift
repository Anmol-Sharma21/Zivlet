import AppKit
import SwiftUI
import Testing
import ZivletCore
import ZivletWheelCore

@testable import ZivletWheel

@Suite("Petal shapes and wheel rendering (P0-42, 03a §2.2)")
struct WheelViewTests {
    let geometry = WheelGeometry.standard
    let rect = CGRect(x: 0, y: 0, width: 372, height: 372)

    /// AppKit polar (y up) → SwiftUI point in the 372 pt frame (y down).
    func point(_ r: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: 186 + r * cos(angle), y: 186 - r * sin(angle))
    }

    @Test(arguments: 2...12)
    func petalCoversItsLabelButNotTheGapHubOrRim(count: Int) {
        let span = 2 * Double.pi / Double(count)
        for slot in 0..<count {
            let path = PetalShape(slot: slot, count: count).path(in: rect)
            let centre = geometry.centreAngle(slot: slot, count: count)
            #expect(path.contains(point(geometry.labelRadius, centre)))
            #expect(path.contains(point(110, centre)) && path.contains(point(55, centre)))
            #expect(!path.contains(point(84, centre + span / 2)))
            #expect(!path.contains(point(30, centre)) && !path.contains(point(122, centre)))
        }
    }

    /// The 1.05 highlight lives in the path (scaled about the wheel centre): `scaleEffect` on a view inside a
    /// `GlassEffectContainer` moved the glass off its petal in the M2 prototype.
    @Test func highlightGrowsThePetalOutwardAroundTheCentre() {
        let centre = geometry.centreAngle(slot: 0, count: 6)
        let grown = PetalShape(slot: 0, count: 6, grow: 1.05).path(in: rect)
        #expect(grown.contains(point(123, centre)) && !grown.contains(point(49.5, centre)))
        #expect(!PetalShape(slot: 0, count: 6).path(in: rect).contains(point(123, centre)))
        var shape = PetalShape(slot: 0, count: 6)
        shape.animatableData = 1.05
        #expect(shape.grow == 1.05)
    }

    @Test func petalsStayInsideTheOuterRadius() {
        for count in 1...12 {
            let bounds = PetalShape(slot: 0, count: count).path(in: rect).boundingRect
            let corners = [bounds.origin, CGPoint(x: bounds.maxX, y: bounds.maxY)]
            #expect(corners.allSatisfy { abs($0.x - 186) <= 119.6 && abs($0.y - 186) <= 119.6 })
        }
    }

    @Test func singleSlotIsAFullRingWithAHole() {
        let ring = PetalShape(slot: 0, count: 1).path(in: rect)
        #expect(ring.contains(point(84, 0)) && ring.contains(point(84, 2)))
        #expect(!ring.contains(CGPoint(x: 186, y: 186)))
        let disk = RingShape(inner: geometry.hubRadius, outer: geometry.ringOuter).path(in: rect)
        #expect(disk.contains(point(124, 1)) && !disk.contains(point(40, 1)) && !disk.contains(point(127, 1)))
    }

    @Test func labelPointsMatchWheelCore() {
        let label = WheelLayout.labelPoint(slot: 0, count: 6)
        #expect(abs(label.x - 186) < 1e-9 && abs(label.y - (186 - geometry.labelRadius)) < 1e-9)
    }

    /// Solid theme pixels: idle petals are dark grey, the highlighted petal takes the accent.
    @Test func solidThemeTintsOnlyTheHighlightedPetal() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.slices(6, highlighted: 0), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        let image = try #require(render(store))
        #expect(image.width == 372 && image.height == 372)
        let hot = try #require(pixel(image, at: point(100, Double.pi / 2)))
        let idle = try #require(pixel(image, at: point(100, -Double.pi / 2)))
        #expect(hot.blue > hot.red + 0.2)
        #expect(abs(idle.red - idle.blue) < 0.05 && idle.red < 0.35)
    }

    /// The hub is a disc, not a hole, so the label never sits on whatever is behind the panel.
    @Test func solidHubIsAnOpaqueDisc() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.slices(6), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        let image = try #require(render(store))
        let hub = try #require(pixel(image, at: point(30, 0.3)))
        #expect(hub.alpha > 0.99 && hub.red < 0.15)
        let outside = try #require(pixel(image, at: point(160, 0.3)))
        #expect(outside.alpha < 0.01)
    }

    /// A soft shadow just outside the rim, none far out, and none inside (it would darken the glass).
    @Test func diskCastsASoftShadowOutsideTheRimOnly() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.slices(6), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        let image = try #require(render(store))
        let below = try #require(pixel(image, at: point(geometry.ringOuter + 4, -Double.pi / 2)))
        #expect(below.alpha > 0.05 && below.red < 0.05)
        let far = try #require(pixel(image, at: point(geometry.ringOuter + 40, -Double.pi / 2)))
        #expect(far.alpha < 0.01)
    }

    /// Solid: a hairline rim lighter than the disk, so the edge shows over dark windows.
    @Test func solidDiskHasALighterRim() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.slices(6), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        let image = try #require(render(store, scale: 4))
        let rim = try #require(pixel(image, at: point(geometry.ringOuter - 0.4, 0.3), scale: 4))
        let disk = try #require(pixel(image, at: point(geometry.ringOuter - 3, 0.3), scale: 4))
        #expect(rim.red > disk.red + 0.05)
    }

    /// FR-26: idle glass petals are darkened under white labels (dark) and lightened under black labels (light).
    /// 0.4 black over the #9D9D9D petal measured on a white window gives about #5E5E5E, 6.4:1 with white.
    @Test func idleGlassScrimOpposesTheLabelColour() {
        #expect(GlassInk.idleScrim(for: .dark) == Color.black.opacity(GlassInk.idleScrimOpacity))
        #expect(GlassInk.idleScrim(for: .light) == Color.white.opacity(GlassInk.idleScrimOpacity))
        #expect(GlassInk.idleScrimOpacity >= 0.3)
    }

    @Test(arguments: 1...9)
    func everySlotCountRendersInBothThemes(count: Int) throws {
        for theme in WheelTheme.allCases {
            let store = WheelStore(feedback: FakeFeedback())
            let appearance = WheelAppearance(theme: theme, palette: Fixtures.appearance.palette, reduceMotion: false)
            store.present(Fixtures.slices(count, highlighted: count - 1), emptyMessage: nil, appearance: appearance)
            store.expand()
            #expect(render(store) != nil)
        }
    }

    @Test func toolLabelsAndEmptyPillRender() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.model(.tools, [.mov]), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        #expect(render(store) != nil)
        let empty = WheelModel(mode: .tools, content: .empty(.noTools(.srt)), idleHubLabel: "a.srt")
        store.present(empty, emptyMessage: "No tools for SRT files", appearance: Fixtures.appearance)
        #expect(render(store) != nil)
        store.dismiss()
        #expect(render(store) != nil)
    }

    func render(_ store: WheelStore, scale: Double = 1) -> CGImage? {
        let renderer = ImageRenderer(content: WheelView(store: store).environment(\.colorScheme, .dark))
        renderer.scale = scale
        return renderer.cgImage
    }

    func pixel(
        _ image: CGImage, at point: CGPoint, scale: Double = 1
    ) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let p = CGPoint(x: point.x * scale, y: point.y * scale)
        let side = 372 * scale
        var data = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: -p.x, y: p.y - Double(image.height) + 1, width: side, height: side))
        return (Double(data[0]) / 255, Double(data[1]) / 255, Double(data[2]) / 255, Double(data[3]) / 255)
    }
}

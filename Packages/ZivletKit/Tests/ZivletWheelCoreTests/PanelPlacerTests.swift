import Testing
import ZivletCore

@testable import ZivletWheelCore

@Suite("Panel placement (P0-26, 03a §2.1)")
struct PanelPlacerTests {
    let placer = PanelPlacer()
    /// 1440 × 900 laptop: 25 pt menu bar on top, no Dock reserve.
    let laptop = ScreenFrame(
        frame: Rect2D(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: Rect2D(x: 0, y: 0, width: 1440, height: 875))
    /// 1920 × 1080 display to the left of the laptop, Dock on its left edge (80 pt).
    let leftDisplay = ScreenFrame(
        frame: Rect2D(x: -1920, y: -180, width: 1920, height: 1080),
        visibleFrame: Rect2D(x: -1840, y: -180, width: 1840, height: 1080))

    /// Disk radius 125.92 plus the 8 pt margin.
    let reach = 133.92

    @Test func centresOnThePointerAwayFromEdges() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 700, y: 400), screens: [laptop]))
        #expect(p.screenIndex == 0)
        #expect(p.wheelCentre == Point2D(x: 700, y: 400))
        #expect(p.offset == .zero)
        #expect(p.panelFrame == Rect2D(x: 514, y: 214, width: 372, height: 372))
    }

    @Test(arguments: [
        (Point2D(x: 5, y: 5), Point2D(x: 133.92, y: 133.92)),
        (Point2D(x: 1435, y: 5), Point2D(x: 1306.08, y: 133.92)),
        (Point2D(x: 5, y: 870), Point2D(x: 133.92, y: 741.08)),
        (Point2D(x: 1435, y: 870), Point2D(x: 1306.08, y: 741.08)),
    ])
    func clampsTheDiskIntoTheVisibleFrameAtCorners(pointer: Point2D, centre: Point2D) throws {
        let p = try #require(placer.place(pointer: pointer, screens: [laptop]))
        #expect(abs(p.wheelCentre.x - centre.x) < 1e-9 && abs(p.wheelCentre.y - centre.y) < 1e-9)
        #expect(abs(p.offset.x) <= reach && abs(p.offset.y) <= reach)
    }

    @Test func menuBarPushesTheWheelDownOnly() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 700, y: 890), screens: [laptop]))
        #expect(p.wheelCentre.x == 700)
        #expect(abs(p.wheelCentre.y - (875 - reach)) < 1e-9)
    }

    @Test func panelMayOverhangTheScreenWhileTheDiskFits() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 140, y: 400), screens: [laptop]))
        #expect(p.wheelCentre.x == 140)
        #expect(p.panelFrame.minX < 0)
    }

    @Test func picksTheScreenUnderThePointerWithNegativeOrigins() throws {
        let p = try #require(
            placer.place(pointer: Point2D(x: -1900, y: -170), screens: [laptop, leftDisplay]))
        #expect(p.screenIndex == 1)
        #expect(abs(p.wheelCentre.x - (-1840 + reach)) < 1e-9)
        #expect(abs(p.wheelCentre.y - (-180 + reach)) < 1e-9)
    }

    @Test func pointerOffEveryScreenFallsBackToTheFirst() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 5000, y: 5000), screens: [laptop, leftDisplay]))
        #expect(p.screenIndex == 0)
        #expect(abs(p.wheelCentre.x - (1440 - reach)) < 1e-9)
    }

    @Test func tinyVisibleFrameCentresTheDisk() throws {
        let tiny = ScreenFrame(
            frame: Rect2D(x: 0, y: 0, width: 200, height: 200),
            visibleFrame: Rect2D(x: 0, y: 0, width: 200, height: 200))
        let p = try #require(placer.place(pointer: Point2D(x: 10, y: 190), screens: [tiny]))
        #expect(p.wheelCentre == Point2D(x: 100, y: 100))
    }

    @Test func noScreensGivesNoPlacement() {
        #expect(placer.place(pointer: .zero, screens: []) == nil)
    }

    @Test func rectContainmentIsHalfOpen() {
        let r = Rect2D(x: 0, y: 0, width: 10, height: 10)
        #expect(r.contains(Point2D(x: 0, y: 0)) && r.contains(Point2D(x: 9.99, y: 9.99)))
        #expect(!r.contains(Point2D(x: 10, y: 5)) && !r.contains(Point2D(x: 5, y: 10)))
        #expect(r.midX == 5 && r.maxY == 10)
    }
}

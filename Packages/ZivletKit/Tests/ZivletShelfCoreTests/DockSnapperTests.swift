import Testing
import ZivletCore

@testable import ZivletShelfCore

@Suite("Dock (attach 28, detach 48, click under 8)")
struct DockSnapperTests {
    private let visible = Rect2D(x: 0, y: 0, width: 1800, height: 1130)

    private func frame(gapFromRight gap: Double) -> Rect2D {
        Rect2D(x: visible.maxX - gap - 384, y: 400, width: 384, height: 300)
    }

    private func frame(gapFromLeft gap: Double) -> Rect2D { Rect2D(x: gap, y: 400, width: 384, height: 300) }

    @Test(arguments: [(27.0, true), (28.0, true), (29.0, false)])
    func attachesNearTheRightEdge(_ gap: Double, _ docks: Bool) {
        #expect(DockSnapper.edge(for: frame(gapFromRight: gap), in: visible, current: nil) == (docks ? .right : nil))
    }

    @Test(arguments: [(27.0, true), (28.0, true), (29.0, false)])
    func attachesNearTheLeftEdge(_ gap: Double, _ docks: Bool) {
        #expect(DockSnapper.edge(for: frame(gapFromLeft: gap), in: visible, current: nil) == (docks ? .left : nil))
    }

    @Test(arguments: [(47.0, true), (48.0, true), (49.0, false)])
    func staysDockedUntilPulledPast48(_ gap: Double, _ stays: Bool) {
        #expect(DockSnapper.edge(for: frame(gapFromRight: gap), in: visible, current: .right) == (stays ? .right : nil))
        #expect(DockSnapper.edge(for: frame(gapFromLeft: gap), in: visible, current: .left) == (stays ? .left : nil))
    }

    @Test func aDockedPanelPulledToTheOtherEdgeDocksThere() {
        #expect(DockSnapper.edge(for: frame(gapFromLeft: 10), in: visible, current: .right) == .left)
    }

    @Test(arguments: [(7.9, true), (8.0, false), (20.0, false)])
    func aMoveUnder8PointsIsAClick(_ distance: Double, _ isClick: Bool) {
        let start = Point2D(x: 100, y: 100)
        #expect(DockSnapper.isClick(from: start, to: Point2D(x: 100 + distance, y: 100)) == isClick)
    }

    @Test func theTabSitsAgainstItsEdgeAtTheFramesHeight() {
        let tab = DockSnapper.tabFrame(edge: .right, panel: frame(gapFromRight: 10), in: visible, width: 28, height: 64)
        #expect(tab == Rect2D(x: visible.maxX - 28, y: 400 + 150 - 32, width: 28, height: 64))
        let left = DockSnapper.tabFrame(edge: .left, panel: frame(gapFromLeft: 0), in: visible, width: 48, height: 64)
        #expect(left.minX == 0 && left.width == 48)
    }
}

@Suite("Panel frames (restore on the right display, clamped inside)")
struct PanelFramesTests {
    private let builtIn = Rect2D(x: 0, y: 0, width: 1800, height: 1130)
    private let external = Rect2D(x: 1800, y: 0, width: 1920, height: 1055)

    @Test func aFrameOnAConnectedDisplayStaysWhereItWas() {
        let frame = Rect2D(x: 2000, y: 200, width: 384, height: 300)
        #expect(PanelFrames.clamped(frame, to: [builtIn, external]) == frame)
    }

    @Test func aFrameOnADisplayThatIsGoneMovesToTheFirstDisplay() {
        let frame = Rect2D(x: 4000, y: 200, width: 384, height: 300)
        let moved = PanelFrames.clamped(frame, to: [builtIn])
        #expect(moved.maxX <= builtIn.maxX && moved.minX >= builtIn.minX && moved.width == 384)
    }

    @Test func aFrameHangingOverAnEdgeIsPulledInside() {
        let frame = Rect2D(x: 1700, y: 1000, width: 384, height: 300)
        let moved = PanelFrames.clamped(frame, to: [builtIn])
        #expect(moved == Rect2D(x: builtIn.maxX - 384, y: builtIn.maxY - 300, width: 384, height: 300))
    }

    @Test func aFrameTallerThanTheDisplayShrinksToFit() {
        let moved = PanelFrames.clamped(Rect2D(x: 0, y: 0, width: 384, height: 5000), to: [builtIn])
        #expect(moved.height == builtIn.height)
    }

    @Test func withoutDisplaysTheFrameIsKept() {
        let frame = Rect2D(x: 1, y: 2, width: 3, height: 4)
        #expect(PanelFrames.clamped(frame, to: []) == frame)
    }

    @Test func aPanelNearADropPointStays12PointsInside() {
        let placed = PanelFrames.placed(width: 384, height: 300, near: Point2D(x: 1790, y: 5), in: builtIn)
        #expect(placed == Rect2D(x: builtIn.maxX - 12 - 384, y: 12, width: 384, height: 300))
        let centred = PanelFrames.placed(width: 384, height: 300, near: Point2D(x: 900, y: 600), in: builtIn)
        #expect(centred.midX == 900 && centred.maxY == 600)
    }

    @Test func theTallestPanelIsSixtyPercentOfTheVisibleHeight() {
        #expect(PanelFrames.maxHeight(in: builtIn) == 678)
    }
}

import Testing
import ZivletCore
import ZivletNotchCore

@Suite("Rect2D in ZivletCore (D-M5a-1)")
struct Rect2DTests {
    @Test func containsIsHalfOpenOnTheMaxEdges() {
        let r = Rect2D(x: 0, y: 0, width: 10, height: 10)
        #expect(r.contains(Point2D(x: 0, y: 0)) && !r.contains(Point2D(x: 10, y: 5)))
    }

    @Test func theCGRectBridgeRoundTrips() {
        let r = Rect2D(x: 1, y: 2, width: 3, height: 4)
        #expect(Rect2D(r.cgRect) == r)
    }
}

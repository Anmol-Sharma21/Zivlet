import SwiftUI
import Testing

@testable import ZivletNotch

@Suite("Island shape (D-N10, 19b D-NL4)")
struct IslandShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 232, height: 62)

    @Test func theIncreaseContrastOutlineIsDrawnInsideTheShapeSoTheClipKeepsAllOfIt() {
        let outline = IslandShape(top: 0, bottom: 12).inset(by: 0.5).path(in: rect).boundingRect
        #expect(outline == rect.insetBy(dx: 0.5, dy: 0.5))
    }

    @Test func insetCornersShrinkWithTheInsetSoTheyStayConcentric() {
        let shape = IslandShape(top: 0, bottom: 12).inset(by: 2)
        #expect(shape.top == 0 && shape.bottom == 10)
    }

    @Test func theTopEdgeSpansTheFrameAndTheBodyIsInsetByTheFlare() {
        let path = IslandShape(top: 0, bottom: 12, flare: 6).path(in: rect)
        #expect(Self.rounded(path.boundingRect) == rect)
        #expect(path.contains(CGPoint(x: 2, y: 0.2)) && path.contains(CGPoint(x: 230, y: 0.2)))  // the flare's lip
        #expect(!path.contains(CGPoint(x: 4, y: 3)) && !path.contains(CGPoint(x: 228, y: 3)))  // the concave cut
        #expect(!path.contains(CGPoint(x: 1, y: 20)) && path.contains(CGPoint(x: 7, y: 20)))  // body inset 6
        #expect(!path.contains(CGPoint(x: 231, y: 20)) && path.contains(CGPoint(x: 225, y: 20)))
    }

    @Test func thePillHasNoFlare() {
        let pill = CGRect(x: 0, y: 0, width: 200, height: 28)
        let path = IslandShape(top: 14, bottom: 14).path(in: pill)
        #expect(path.boundingRect == pill)
        #expect(!path.contains(CGPoint(x: 0.5, y: 0.5)) && !path.contains(CGPoint(x: 199.5, y: 0.5)))
        #expect(path.contains(CGPoint(x: 100, y: 0.5)))
    }

    @Test func theFlareAnimatesWithTheRadii() {
        var shape = IslandShape(top: 0, bottom: 12, flare: 6)
        #expect(shape.animatableData.first == 0 && shape.animatableData.second.first == 12)
        #expect(shape.animatableData.second.second == 6)
        shape.animatableData = AnimatablePair(4, AnimatablePair(20, 3))
        #expect(shape.top == 4 && shape.bottom == 20 && shape.flare == 3)
    }

    @Test func theOutlineInsetKeepsTheBodySidesInside() {
        let path = IslandShape(top: 0, bottom: 12, flare: 6).inset(by: 0.5).path(in: rect)
        #expect(Self.rounded(path.boundingRect) == rect.insetBy(dx: 0.5, dy: 0.5))
        #expect(!path.contains(CGPoint(x: 6.3, y: 20)) && path.contains(CGPoint(x: 6.7, y: 20)))
    }

    @Test func aFlareWiderThanTheShapeIsLimited() {
        let tiny = CGRect(x: 0, y: 0, width: 20, height: 10)
        let path = IslandShape(top: 0, bottom: 12, flare: 40).path(in: tiny)
        #expect(path.boundingRect.width <= 20 && !path.isEmpty)
    }

    /// The body and its two lips are one closed contour, so a stroke of it has no seam where a lip meets a side.
    @Test func theNotchShapeIsOneContour() {
        #expect(Self.subpaths(IslandShape(top: 0, bottom: 12, flare: 6).path(in: rect)) == 1)
        #expect(Self.subpaths(IslandShape(top: 0, bottom: 12, flare: 6).inset(by: 0.5).path(in: rect)) == 1)
        #expect(Self.subpaths(IslandShape(top: 14, bottom: 14).path(in: rect)) == 1)
    }

    /// Increase Contrast on a notch display: the outline runs down the lips, the sides and the bottom, but nothing is
    /// drawn along the screen edge (the top) beside the housing or across it; the pill keeps its whole outline.
    @Test func theNotchOutlineIsOpenAtTheScreenEdge() {
        let outline = IslandOutline(shape: IslandShape(top: 0, bottom: 12, flare: 6), lineWidth: 1).path(in: rect)
        #expect(!outline.contains(CGPoint(x: 116, y: 0.5)) && !outline.contains(CGPoint(x: 1, y: 0.5)))
        #expect(outline.contains(CGPoint(x: 6.5, y: 30)) && outline.contains(CGPoint(x: 225.5, y: 30)))
        #expect(outline.contains(CGPoint(x: 116, y: 61.5)))
        #expect(!outline.contains(CGPoint(x: 116, y: 30)))  // only a line, not a fill
        let pill = CGRect(x: 0, y: 0, width: 200, height: 28)
        let closed = IslandOutline(shape: IslandShape(top: 14, bottom: 14), lineWidth: 1).path(in: pill)
        #expect(closed.contains(CGPoint(x: 100, y: 0.5)) && closed.contains(CGPoint(x: 100, y: 27.5)))
    }

    /// The number of closed or open subpaths (each starts with a move).
    private static func subpaths(_ path: Path) -> Int {
        var count = 0
        path.forEach { if case .move = $0 { count += 1 } }
        return count
    }

    /// Bounds to a thousandth of a point: arcs leave rounding noise far below a pixel.
    private static func rounded(_ rect: CGRect) -> CGRect {
        func r(_ value: CGFloat) -> CGFloat { (value * 1_000).rounded() / 1_000 }
        return CGRect(x: r(rect.minX), y: r(rect.minY), width: r(rect.width), height: r(rect.height))
    }
}

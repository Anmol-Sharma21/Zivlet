import SwiftUI

/// The island's outline (D-N3, 19b D-NL4). On a notch display the top edge is as wide as the frame and flush with the
/// screen edge; a concave curve of radius `flare` brings each side in to the body, whose bottom corners round. The
/// pill has no flare and rounds all four corners. Continuous corners; radii and flare animate. Insettable, so the
/// Increase Contrast outline can be drawn inside the edge and survive the clip whole. The body and its lips are one
/// closed contour, so a stroke of it has no seam where a lip meets a side.
nonisolated struct IslandShape: InsettableShape {
    var top: Double
    var bottom: Double
    var flare: Double
    private var insetAmount = 0.0

    init(top: Double, bottom: Double, flare: Double = 0) {
        self.top = top
        self.bottom = bottom
        self.flare = flare
    }

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(top, AnimatablePair(bottom, flare)) }
        set {
            top = newValue.first
            bottom = newValue.second.first
            flare = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let inner = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let flare = max(0, min(self.flare, inner.width / 4, inner.height / 2))
        let body = inner.insetBy(dx: flare, dy: 0)
        let limit = min(body.width, body.height) / 2
        let path = UnevenRoundedRectangle(
            topLeadingRadius: min(top, limit), bottomLeadingRadius: min(bottom, limit),
            bottomTrailingRadius: min(bottom, limit), topTrailingRadius: min(top, limit), style: .continuous
        ).path(in: body)
        guard flare > 0 else { return path }
        let left = Self.lip(at: CGPoint(x: body.minX, y: body.minY), outward: -1, radius: flare)
        let right = Self.lip(at: CGPoint(x: body.maxX, y: body.minY), outward: 1, radius: flare)
        return path.union(left).union(right)
    }

    /// The same shape `amount` inside: the corners shrink by as much, so the two outlines stay concentric. The flare
    /// keeps its radius so the body's sides move in by `amount` too.
    func inset(by amount: CGFloat) -> IslandShape {
        var next = self
        next.insetAmount += amount
        next.top = max(0, top - amount)
        next.bottom = max(0, bottom - amount)
        return next
    }

    /// The wedge between the top edge, the body's side and a concave quarter circle: it joins the body at `corner`
    /// and reaches `radius` outward along the top edge. It reaches `overlap` into the body too, so the union never
    /// meets the body along a shared edge only.
    private static func lip(at corner: CGPoint, outward: Double, radius: Double) -> Path {
        let inside = corner.x - outward * overlap
        return Path { path in
            path.move(to: CGPoint(x: inside, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x + outward * radius, y: corner.y))
            path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x, y: corner.y + radius), radius: radius)
            path.addLine(to: CGPoint(x: inside, y: corner.y + radius))
            path.closeSubpath()
        }
    }

    private static let overlap = 1.0
}

/// The Increase Contrast outline (19b §7): the shape's edge as a line `lineWidth` wide, inside the edge. On a notch
/// display (a flare) the top is left open, so nothing is drawn along the screen edge beside or across the housing;
/// the pill keeps its whole outline.
nonisolated struct IslandOutline: Shape {
    var shape: IslandShape
    let lineWidth: Double

    var animatableData: IslandShape.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let line = shape.inset(by: lineWidth / 2).path(in: rect).strokedPath(StrokeStyle(lineWidth: lineWidth))
        guard shape.flare > 0 else { return line }
        return line.subtracting(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: lineWidth)))
    }
}

import SwiftUI

/// The island's outline (D-N3, 19b D-NL4). On a notch display the top edge is as wide as the frame and flush with the
/// screen edge; a concave curve of radius `flare` brings each side in to the body, whose bottom corners round. The
/// pill has no flare and rounds all four corners. Continuous corners; radii and flare animate. Insettable, so the
/// Increase Contrast outline can be drawn inside the edge and survive the clip whole.
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
        var path = UnevenRoundedRectangle(
            topLeadingRadius: min(top, limit), bottomLeadingRadius: min(bottom, limit),
            bottomTrailingRadius: min(bottom, limit), topTrailingRadius: min(top, limit), style: .continuous
        ).path(in: body)
        guard flare > 0 else { return path }
        path.addPath(Self.lip(at: CGPoint(x: body.minX, y: body.minY), outward: -1, radius: flare))
        path.addPath(Self.lip(at: CGPoint(x: body.maxX, y: body.minY), outward: 1, radius: flare))
        return path
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
    /// and reaches `radius` outward along the top edge.
    private static func lip(at corner: CGPoint, outward: Double, radius: Double) -> Path {
        Path { path in
            path.move(to: corner)
            path.addLine(to: CGPoint(x: corner.x + outward * radius, y: corner.y))
            path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x, y: corner.y + radius), radius: radius)
            path.closeSubpath()
        }
    }
}

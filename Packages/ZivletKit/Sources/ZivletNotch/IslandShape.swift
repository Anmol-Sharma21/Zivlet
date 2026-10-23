import SwiftUI

/// The island's outline (D-N3): on a notch display the top corners are square, flush with the screen edge, and the
/// bottom corners round; the pill rounds all four. Continuous corners; both radii animate. Insettable, so the
/// Increase Contrast outline (D-N10) can be drawn inside the edge and survive the clip whole.
nonisolated struct IslandShape: InsettableShape {
    var top: Double
    var bottom: Double
    private var insetAmount = 0.0

    init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(top, bottom) }
        set {
            top = newValue.first
            bottom = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let inner = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let limit = min(inner.width, inner.height) / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: min(top, limit), bottomLeadingRadius: min(bottom, limit),
            bottomTrailingRadius: min(bottom, limit), topTrailingRadius: min(top, limit), style: .continuous
        ).path(in: inner)
    }

    /// The same shape `amount` inside: the corners shrink by as much, so the two outlines stay concentric.
    func inset(by amount: CGFloat) -> IslandShape {
        var next = self
        next.insetAmount += amount
        next.top = max(0, top - amount)
        next.bottom = max(0, bottom - amount)
        return next
    }
}

import SwiftUI

/// The island's outline (D-N3): on a notch display the top corners are square, flush with the screen edge, and the
/// bottom corners round; the pill rounds all four. Continuous corners; both radii animate.
nonisolated struct IslandShape: Shape {
    var top: Double
    var bottom: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(top, bottom) }
        set {
            top = newValue.first
            bottom = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: min(top, limit), bottomLeadingRadius: min(bottom, limit),
            bottomTrailingRadius: min(bottom, limit), topTrailingRadius: min(top, limit), style: .continuous
        ).path(in: rect)
    }
}

import SwiftUI

/// The island's ink (D-N10, design/19 §5.5): white on solid black, secondary text white at 0.8, the ring's track
/// white at 0.4. The contrast checks reuse `HUDInk.luminance`.
enum NotchInk {
    static let secondaryOpacity = 0.8
    static let ringTrackOpacity = 0.4
    static let ringLineWidth: CGFloat = 2.5
    static let glyphSide: CGFloat = 14

    static let primary = Color.white
    static let secondary = Color.white.opacity(secondaryOpacity)
    static let track = Color.white.opacity(ringTrackOpacity)

    /// WCAG contrast of white at `textOpacity` over the black island.
    static func contrast(textOpacity: Double) -> Double { ratio(textOpacity, 0) }

    /// WCAG contrast between the ring's fill and its track, both white at their opacities over black.
    static func contrast(fill: Double, track: Double) -> Double { ratio(fill, track) }

    private static func ratio(_ first: Double, _ second: Double) -> Double {
        let (a, b) = (HUDInk.luminance(first), HUDInk.luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

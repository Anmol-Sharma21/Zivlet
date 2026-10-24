import SwiftUI

/// The island's ink (D-N10, 19b D-NL11, §3.5): white, secondary text white at 0.8, the ring's and bar's track white at
/// 0.3, on black, glass and the solid finish alike; no accent colour. Contrast is computed by compositing white at its
/// opacity over a surface in sRGB, as `HUDInk.worstContrast` does.
enum NotchInk {
    static let secondaryOpacity = 0.8
    static let trackOpacity = 0.3
    /// M5a's ring track, until the glyphs move to the tokens.
    static let ringTrackOpacity = 0.4
    static let ringLineWidth: CGFloat = 2.5
    static let glyphSide: CGFloat = 14

    static let primary = Color.white
    static let secondary = Color.white.opacity(secondaryOpacity)
    static let track = Color.white.opacity(ringTrackOpacity)

    /// WCAG contrast of white at `textOpacity` over the black island.
    static func contrast(textOpacity: Double) -> Double { contrast(textOpacity: textOpacity, over: 0) }

    /// WCAG contrast between the ring's fill and its track, both white at their opacities over black.
    static func contrast(fill: Double, track: Double) -> Double { contrast(fill: fill, track: track, over: 0) }

    /// WCAG contrast of white text at `textOpacity` over a surface of linear luminance `surface`.
    static func contrast(textOpacity: Double, over surface: Double) -> Double {
        ratio(HUDInk.luminance(white(textOpacity, over: surface)), surface)
    }

    /// WCAG contrast of the ring's or bar's white fill against the surface (non-text, ≥ 3:1).
    static func contrast(fillOver surface: Double) -> Double { contrast(textOpacity: 1, over: surface) }

    /// WCAG contrast between the fill and the track, both white at their opacities over the surface.
    static func contrast(fill: Double, track: Double, over surface: Double) -> Double {
        ratio(HUDInk.luminance(white(fill, over: surface)), HUDInk.luminance(white(track, over: surface)))
    }

    /// sRGB grey of a surface of linear luminance `luminance`.
    static func grey(ofLuminance luminance: Double) -> Double {
        luminance <= 0.0031308 ? luminance * 12.92 : 1.055 * pow(luminance, 1 / 2.4) - 0.055
    }

    /// sRGB grey of white at `opacity` over the surface.
    private static func white(_ opacity: Double, over surface: Double) -> Double {
        opacity + grey(ofLuminance: surface) * (1 - opacity)
    }

    private static func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
}

import Foundation
import SwiftUI

/// The island's ink (D-N10, 19b D-NL11, §3.5): white, secondary text white at 0.8, the ring's and bar's track white at
/// 0.3, on black, glass and the solid finish alike; no accent colour. Contrast is computed by compositing white at its
/// opacity over a surface in sRGB. Shared by the notch HUD and the Drop Box (plan 16 D-M5b-22).
public enum IslandInk {
    public static let secondaryOpacity = 0.8
    public static let trackOpacity = 0.3

    public static let primary = Color.white
    public static let secondary = Color.white.opacity(secondaryOpacity)
    public static let track = Color.white.opacity(trackOpacity)

    /// WCAG contrast of white at `textOpacity` over the black island.
    public static func contrast(textOpacity: Double) -> Double { contrast(textOpacity: textOpacity, over: 0) }

    /// WCAG contrast between the ring's fill and its track, both white at their opacities over black.
    public static func contrast(fill: Double, track: Double) -> Double { contrast(fill: fill, track: track, over: 0) }

    /// WCAG contrast of white text at `textOpacity` over a surface of linear luminance `surface`.
    public static func contrast(textOpacity: Double, over surface: Double) -> Double {
        ratio(luminance(white(textOpacity, over: surface)), surface)
    }

    /// WCAG contrast of the ring's or bar's white fill against the surface (non-text, ≥ 3:1).
    public static func contrast(fillOver surface: Double) -> Double { contrast(textOpacity: 1, over: surface) }

    /// WCAG contrast between the fill and the track, both white at their opacities over the surface.
    public static func contrast(fill: Double, track: Double, over surface: Double) -> Double {
        ratio(luminance(white(fill, over: surface)), luminance(white(track, over: surface)))
    }

    /// WCAG contrast of white at `textOpacity` over black at `circleOpacity` over a surface of linear luminance
    /// `surface`: a badge symbol on its dark circle over a thumbnail (19c §3.6).
    public static func contrast(textOpacity: Double, overBlack circleOpacity: Double, over surface: Double) -> Double {
        let circle = grey(ofLuminance: surface) * (1 - circleOpacity)
        let text = textOpacity + circle * (1 - textOpacity)
        return ratio(luminance(text), luminance(circle))
    }

    /// Linear luminance of an sRGB grey level.
    public static func luminance(_ grey: Double) -> Double {
        grey <= 0.04045 ? grey / 12.92 : pow((grey + 0.055) / 1.055, 2.4)
    }

    /// sRGB grey of a surface of linear luminance `luminance`.
    public static func grey(ofLuminance luminance: Double) -> Double {
        luminance <= 0.0031308 ? luminance * 12.92 : 1.055 * pow(luminance, 1 / 2.4) - 0.055
    }

    /// sRGB grey of white at `opacity` over the surface.
    private static func white(_ opacity: Double, over surface: Double) -> Double {
        opacity + grey(ofLuminance: surface) * (1 - opacity)
    }

    private static func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
}

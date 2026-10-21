import Foundation
import SwiftUI

/// Text ink for the HUD's glass (NFR-14 ≥ 4.5:1): a colour-scheme scrim under the content, and secondary text at a
/// fixed opacity of the primary colour instead of `.secondary`. The values hold even when the glass lets the
/// backdrop through untouched: a white desktop behind dark-mode white text, a black one behind light-mode black
/// text (the worst cases; real glass frosts the backdrop toward grey).
enum HUDInk {
    static let scrimOpacity = 0.65
    static let secondaryOpacity = 0.8
    static let cornerRadius: CGFloat = 18

    static func scrim(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.black : Color.white).opacity(scrimOpacity)
    }

    static let secondary = Color.primary.opacity(secondaryOpacity)

    /// WCAG contrast of text at `textOpacity` over the scrim over the worst backdrop, as sRGB grey levels.
    static func worstContrast(scheme: ColorScheme, textOpacity: Double) -> Double {
        let (ink, scrim, backdrop): (Double, Double, Double) = scheme == .dark ? (1, 0, 1) : (0, 1, 0)
        let surface = scrim * scrimOpacity + backdrop * (1 - scrimOpacity)
        let text = ink * textOpacity + surface * (1 - textOpacity)
        let (a, b) = (luminance(text), luminance(surface))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func luminance(_ grey: Double) -> Double {
        grey <= 0.04045 ? grey / 12.92 : pow((grey + 0.055) / 1.055, 2.4)
    }
}

/// The HUD surface: the scrim, then Liquid Glass behind it, in the HUD's rounded rectangle.
struct HUDGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(HUDInk.scrim(for: colorScheme), in: .rect(cornerRadius: HUDInk.cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: HUDInk.cornerRadius))
    }
}

extension View {
    func hudGlass() -> some View { modifier(HUDGlass()) }
}

import AppKit
import SwiftUI

/// sRGB colour, components clamped to 0…1. Pure maths so the palette rules are testable.
public struct RGB: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    public static let white = RGB(r: 1, g: 1, b: 1)
    public static let black = RGB(r: 0, g: 0, b: 0)

    /// Hue in 0…1 (fraction of a turn).
    public init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue * 6).truncatingRemainder(dividingBy: 6)
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - chroma
        let (r, g, b): (Double, Double, Double) =
            switch Int(sector) {
            case 0: (chroma, x, 0)
            case 1: (x, chroma, 0)
            case 2: (0, chroma, x)
            case 3: (0, x, chroma)
            case 4: (x, 0, chroma)
            default: (chroma, 0, x)
            }
        self.init(r: r + m, g: g + m, b: b + m)
    }

    /// Converts any colour to sRGB; colours without RGB components fall back to mid grey.
    public init(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            self.init(r: 0.5, g: 0.5, b: 0.5)
            return
        }
        self.init(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
    }

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let high = max(r, g, b)
        let delta = high - min(r, g, b)
        guard delta > 0 else { return (0, 0, high) }
        let raw: Double =
            if high == r { ((g - b) / delta).truncatingRemainder(dividingBy: 6) } else if high == g {
                (b - r) / delta + 2
            } else { (r - g) / delta + 4 }
        let hue = raw / 6
        return (hue < 0 ? hue + 1 : hue, delta / high, high)
    }

    public func mixed(with other: RGB, amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    public func contrast(with other: RGB) -> Double {
        let (light, dark) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

/// One accent token and its derived stops (03a §2.7): light = +24 % white; dark = saturation × 1.12 (capped),
/// brightness × 0.74. The base hue is Zivlet's choice: the user's system accent colour (08 index D-M2-4).
public struct AccentPalette: Sendable, Equatable {
    public let base: RGB
    public let light: RGB
    public let dark: RGB

    public init(base: RGB) {
        self.base = base
        light = base.mixed(with: .white, amount: 0.24)
        let (h, s, b) = base.hsb
        dark = RGB(hue: h, saturation: min(s * 1.12, 1), brightness: b * 0.74)
    }

    public static var system: AccentPalette { AccentPalette(base: RGB(NSColor.controlAccentColor)) }

    /// White or black, whichever contrasts more with the base (01-prd FR-26 asks ≥ 4.5:1 where reachable).
    public var labelOnAccent: RGB { base.contrast(with: .white) >= base.contrast(with: .black) ? .white : .black }
}

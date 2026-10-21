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
///
/// The highlighted petal paints light → base → dark, and its label can sit over most of that (side slots, two-line
/// action labels). The label is white or black, whichever has the higher worst case over every painted stop. When
/// even that is below 4.5:1 (01-prd FR-26), light and dark are pulled toward base in steps of 0.1 until it is not
/// (`strength`). A flat base always reaches 4.58:1 with one of the two, so the loop ends (D-M4-17).
public struct AccentPalette: Sendable, Equatable {
    public static let minimumContrast = 4.5
    static let strengthStep = 0.1

    public let base: RGB
    public let light: RGB
    public let dark: RGB
    /// How much of `light` and `dark` the highlight paints: 1 = the 03a stops, 0 = flat base.
    public let strength: Double
    /// White or black for the highlighted petal's label.
    public let labelOnAccent: RGB

    public init(base: RGB) {
        self.base = base
        let light = base.mixed(with: .white, amount: 0.24)
        let (h, s, b) = base.hsb
        let dark = RGB(hue: h, saturation: min(s * 1.12, 1), brightness: b * 0.74)
        self.light = light
        self.dark = dark
        let (strength, label) = Self.legible(base: base, light: light, dark: dark)
        self.strength = strength
        labelOnAccent = label
    }

    public static var system: AccentPalette { AccentPalette(base: RGB(NSColor.controlAccentColor)) }

    public var paintedLight: RGB { strength == 1 ? light : base.mixed(with: light, amount: strength) }
    public var paintedDark: RGB { strength == 1 ? dark : base.mixed(with: dark, amount: strength) }

    /// Colours along the painted gradient, light to dark.
    public var highlightSamples: [RGB] { Self.samples(base: base, light: paintedLight, dark: paintedDark) }

    /// The strongest gradient (from 1 down) whose better label colour reaches `minimumContrast` everywhere.
    static func legible(base: RGB, light: RGB, dark: RGB) -> (strength: Double, label: RGB) {
        let steps = Int((1 / strengthStep).rounded())
        for step in stride(from: steps, through: 0, by: -1) {
            let strength = Double(step) * strengthStep
            let samples = samples(
                base: base, light: base.mixed(with: light, amount: strength),
                dark: base.mixed(with: dark, amount: strength))
            let (label, worst) = betterLabel(over: samples)
            if worst >= minimumContrast || step == 0 { return (strength, label) }
        }
        return (0, betterLabel(over: [base]).label)
    }

    /// White or black, whichever has the higher lowest contrast over `samples`.
    static func betterLabel(over samples: [RGB]) -> (label: RGB, worst: Double) {
        let white = samples.map { $0.contrast(with: .white) }.min() ?? 0
        let black = samples.map { $0.contrast(with: .black) }.min() ?? 0
        return white >= black ? (.white, white) : (.black, black)
    }

    static func samples(base: RGB, light: RGB, dark: RGB) -> [RGB] {
        let fractions = (0...10).map { Double($0) / 10 }
        return fractions.map { light.mixed(with: base, amount: $0) }
            + fractions.map { base.mixed(with: dark, amount: $0) }
    }
}

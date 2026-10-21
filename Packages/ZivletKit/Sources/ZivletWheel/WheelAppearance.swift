import AppKit

/// Glass (Liquid Glass petals) or Solid (opaque, high contrast) (01-prd FR-26).
public enum WheelTheme: String, Sendable, CaseIterable {
    case glass, solid

    /// Defaults value of `ZivletWheelTheme`; anything unknown means glass.
    public init(preference: String?) {
        self = preference.flatMap(WheelTheme.init(rawValue:)) ?? .glass
    }

    /// Solid is forced under Reduce Transparency or Increase Contrast (03a §2.7).
    public static func resolve(preference: WheelTheme, reduceTransparency: Bool, increaseContrast: Bool) -> WheelTheme {
        reduceTransparency || increaseContrast ? .solid : preference
    }
}

/// Everything visual that is decided once per show.
public struct WheelAppearance: Sendable, Equatable {
    public static let themeKey = "ZivletWheelTheme"

    public let theme: WheelTheme
    public let palette: AccentPalette
    public let reduceMotion: Bool

    public init(theme: WheelTheme, palette: AccentPalette, reduceMotion: Bool) {
        self.theme = theme
        self.palette = palette
        self.reduceMotion = reduceMotion
    }

    /// Reads the theme preference (launch arguments `-ZivletWheelTheme solid` land here too) and the system
    /// accessibility switches.
    public static func current(defaults: UserDefaults = .standard) -> WheelAppearance {
        let workspace = NSWorkspace.shared
        let theme = WheelTheme.resolve(
            preference: WheelTheme(preference: defaults.string(forKey: themeKey)),
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
        return WheelAppearance(
            theme: theme, palette: .system, reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}

/// Animation numbers (03a §2.7, 05 P0-42), in one place.
enum WheelTiming {
    static let fadeIn = 0.07
    static let introScale = 0.45
    static let intro = 0.20
    static let labelsDelay = 0.05
    static let labels = 0.10
    static let highlight = 0.12
    static let morph = 0.28
    static let morphBounce = 0.15
    static let shake = 0.24
    static let hide = 0.08
    static let reducedMotionFade = 0.08
}

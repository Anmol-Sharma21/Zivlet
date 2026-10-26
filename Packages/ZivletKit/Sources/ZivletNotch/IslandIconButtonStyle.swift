import SwiftUI

/// The island's icon button background (19b D-NL9): no border and no fill at rest, white 0.14 on hover and 0.22 while
/// pressed; under Increase Contrast (the outlined finish) the round background shows at rest. Shared by the notch HUD
/// and the Drop Box (plan 16 D-M5b-22).
public enum IslandIconButtonFill {
    public static let hover = 0.14
    public static let pressed = 0.22
    public static let contrast = 0.18

    /// The round background at rest: none, or white 0.18 under Increase Contrast (19b §7).
    public static func resting(increaseContrast: Bool) -> Double { increaseContrast ? contrast : 0 }

    /// The background's opacity for a state.
    public static func opacity(pressed isPressed: Bool, hovered: Bool, increaseContrast: Bool) -> Double {
        if isPressed { return pressed }
        if hovered { return hover }
        return resting(increaseContrast: increaseContrast)
    }

    /// The hover fill eases in over 0.12 s; under Reduce Motion it changes at once (19b §3.4).
    public static func hoverAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
}

/// The circle behind the symbol; hover through `onHover`, so no global event monitor is needed.
public struct IslandIconButtonStyle: ButtonStyle {
    /// The island's outline, from the same finish as the outline itself (not SwiftUI's own contrast reading).
    @Environment(\.islandOutlined) private var outlined
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let opacity = IslandIconButtonFill.opacity(
            pressed: configuration.isPressed, hovered: hovered, increaseContrast: outlined)
        return configuration.label
            .background(Circle().fill(Color.white.opacity(opacity)))
            .onHover { hovered = $0 }
            .animation(IslandIconButtonFill.hoverAnimation(reduceMotion: reduceMotion), value: hovered)
    }
}

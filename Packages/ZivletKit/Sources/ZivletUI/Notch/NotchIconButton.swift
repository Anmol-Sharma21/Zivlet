import SwiftUI

/// An island button drawn as an SF Symbol in a 28 pt round hit area (19b D-NL9): no border and no fill at rest, white
/// 0.14 on hover and 0.22 while pressed. Its tooltip and accessibility label are today's button title, so Voice
/// Control's "click Undo" and the M5a words still work. Under Increase Contrast the round background shows at rest.
struct NotchIconButton: View {
    static let hoverFill = 0.14
    static let pressedFill = 0.22
    static let contrastFill = 0.18

    let press: NotchHUD.Press
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol ?? Self.symbol(press))
                .font(NotchLook.Symbol.button)
                .foregroundStyle(NotchInk.primary)
                .frame(width: NotchLook.Symbol.buttonSide, height: NotchLook.Symbol.buttonSide)
                .contentShape(Circle())
        }
        .buttonStyle(NotchIconButtonStyle())
        .help(Self.title(press))
        .accessibilityLabel(Self.title(press))
    }

    /// Today's words for the press (the M5a button titles), unchanged.
    static func title(_ press: NotchHUD.Press) -> String { NotchListRow.title(press) }

    /// The symbol of 19b §3.3.
    static func symbol(_ press: NotchHUD.Press) -> String {
        switch press {
        case .cancel: "xmark"
        case .undo: "arrow.uturn.backward"
        case .reveal: "folder"
        case .open: "arrow.up.forward.app"
        case .copy: "doc.on.doc"
        case .showDetails: "chevron.down"
        case .retry: "arrow.clockwise"
        case .close: "xmark.circle"
        }
    }

    /// The round background at rest: none, or white 0.18 under Increase Contrast (19b §7).
    static func restingFill(increaseContrast: Bool) -> Double { increaseContrast ? contrastFill : 0 }

    /// The hover fill eases in over 0.12 s; under Reduce Motion it changes at once (19b §3.4).
    static func hoverAnimation(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.12) }

    /// The background's opacity for a state.
    static func fill(pressed: Bool, hovered: Bool, increaseContrast: Bool) -> Double {
        if pressed { return pressedFill }
        if hovered { return hoverFill }
        return restingFill(increaseContrast: increaseContrast)
    }
}

/// The circle behind the symbol; hover through `onHover`, so no global event monitor is needed.
struct NotchIconButtonStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let opacity = NotchIconButton.fill(
            pressed: configuration.isPressed, hovered: hovered, increaseContrast: contrast == .increased)
        return configuration.label
            .background(Circle().fill(Color.white.opacity(opacity)))
            .onHover { hovered = $0 }
            .animation(NotchIconButton.hoverAnimation(reduceMotion: reduceMotion), value: hovered)
    }
}

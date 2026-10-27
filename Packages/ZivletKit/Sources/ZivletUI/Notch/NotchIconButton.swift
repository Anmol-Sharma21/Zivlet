import SwiftUI
import ZivletNotch

/// An island button drawn as an SF Symbol in a 28 pt round hit area (19b D-NL9): no border and no fill at rest, white
/// 0.14 on hover and 0.22 while pressed. Its tooltip and accessibility label are today's button title, so Voice
/// Control's "click Undo" and the M5a words still work. Under Increase Contrast (the island's outlined finish) the round
/// background shows at rest.
struct NotchIconButton: View {
    static let hoverFill = IslandIconButtonFill.hover
    static let pressedFill = IslandIconButtonFill.pressed
    static let contrastFill = IslandIconButtonFill.contrast

    let press: NotchHUD.Press
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        IslandSymbolButton(symbol: symbol ?? Self.symbol(press), title: Self.title(press), action: action)
    }

    /// Today's words for the press (the M5a button titles), unchanged.
    static func title(_ press: NotchHUD.Press) -> String { NotchListRow.title(press) }

    /// The symbol of 19b §3.3. Cancel was an X, then a filled square (it read as an empty checkbox), now a circle.
    static func symbol(_ press: NotchHUD.Press) -> String {
        switch press {
        case .cancel: "stop.circle"  // stops a conversion: not the X that only dismisses; outlined like Close
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
    static func restingFill(increaseContrast: Bool) -> Double {
        IslandIconButtonFill.resting(increaseContrast: increaseContrast)
    }

    /// The hover fill eases in over 0.12 s; under Reduce Motion it changes at once (19b §3.4).
    static func hoverAnimation(reduceMotion: Bool) -> Animation? {
        IslandIconButtonFill.hoverAnimation(reduceMotion: reduceMotion)
    }

    /// The background's opacity for a state.
    static func fill(pressed: Bool, hovered: Bool, increaseContrast: Bool) -> Double {
        IslandIconButtonFill.opacity(pressed: pressed, hovered: hovered, increaseContrast: increaseContrast)
    }
}

/// One island symbol button: the symbol in the 28 pt round hit area with the island's hover and press fills, the
/// title as its tooltip and (unless `label` says otherwise) its accessibility label.
struct IslandSymbolButton: View {
    let symbol: String
    let title: String
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(NotchLook.Symbol.button)
                .foregroundStyle(NotchInk.primary)
                .frame(width: NotchLook.Symbol.buttonSide, height: NotchLook.Symbol.buttonSide)
                .contentShape(Circle())
        }
        .buttonStyle(IslandIconButtonStyle())
        .help(title)
        .accessibilityLabel(label ?? title)
    }
}

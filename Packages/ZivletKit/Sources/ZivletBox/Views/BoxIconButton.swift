import SwiftUI
import ZivletNotch

/// A box button: an SF Symbol in the island's 28 pt round hit area (19b D-NL9, 19c D-BL5), with its words as tooltip
/// and accessibility label.
struct BoxIconButton: View {
    let press: BoxPress
    var symbol: String? = nil
    var title: String? = nil
    let action: (BoxPress) -> Void

    var body: some View {
        Button {
            action(press)
        } label: {
            BoxSymbolLabel(symbol: symbol ?? press.symbol)
        }
        .buttonStyle(IslandIconButtonStyle())
        .help(title ?? BoxCopy.title(press))
        .accessibilityLabel(title ?? BoxCopy.title(press))
    }
}

/// The symbol inside an icon button or menu label.
struct BoxSymbolLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(IslandContentLook.Symbol.button)
            .foregroundStyle(IslandInk.primary)
            .frame(width: IslandContentLook.Symbol.buttonSide, height: IslandContentLook.Symbol.buttonSide)
            .contentShape(Circle())
    }
}

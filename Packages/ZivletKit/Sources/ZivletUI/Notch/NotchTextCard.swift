import SwiftUI
import ZivletActions
import ZivletNotch

/// The island's text card (P2-104, 19b look): the saved glyph and "Text copied", up to three preview lines and the
/// count line in the island's secondary ink, and the three buttons as island icon buttons.
struct NotchTextCard: View {
    /// NFR-14: white at 0.8 over the black island.
    static let lineOpacity = IslandInk.secondaryOpacity

    let toast: String
    let model: TextResultModel
    let width: CGFloat
    let press: (TextResultButton) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: NotchLook.Spacing.s) {
            NotchSymbol(name: NotchSymbol.saved)
            VStack(alignment: .leading, spacing: NotchLook.Spacing.xs) {
                Text(toast).font(NotchLook.TypeStyle.primary).foregroundStyle(NotchInk.primary).lineLimit(1)
                ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(NotchLook.TypeStyle.secondary).foregroundStyle(NotchInk.secondary).lineLimit(1)
                }
                HStack(alignment: .bottom, spacing: NotchLook.Spacing.s) {
                    VStack(alignment: .leading, spacing: NotchLook.Spacing.xs) {
                        NotchCaption(text: model.countLine)
                        if let saved = model.savedLine { NotchCaption(text: saved) }
                    }
                    .layoutPriority(1)
                    HStack(spacing: NotchLook.Spacing.xs) {
                        Spacer(minLength: 0)
                        ForEach(model.buttons, id: \.self) { button in
                            IslandSymbolButton(
                                symbol: button.symbol, title: button.title, label: button.accessibilityLabel
                            ) { press(button) }
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }
}

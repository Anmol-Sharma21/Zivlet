import SwiftUI
import ZivletNotchCore

/// The toast row (design/19 §4.3): a check mark, the error glyph or an action icon, the board's line, and Undo when
/// an action offers it. VoiceOver reads the board's spoken form, with separators as words.
struct NotchToast: View {
    static let sidePadding: CGFloat = 14

    let model: NotchHUDModel
    let display: UInt32
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let glyph = model.board.toastGlyph(on: display) { NotchSymbol(name: NotchSymbol.name(for: glyph)) }
            if let line = model.board.toastLine(on: display) {
                Text(line).font(.callout.weight(.medium)).foregroundStyle(NotchInk.primary).lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(model.board.toastAccessibilityLabel(on: display) ?? line)
            }
            Spacer(minLength: 0)
            if let id = undoable { Button("Undo") { act(.undo, id) }.controlSize(.small) }
        }
        .padding(.horizontal, Self.sidePadding)
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.Metrics.toastRow)
    }

    /// The toast's action, when it offers Undo now.
    private var undoable: NotchHUDItemID? {
        guard let item = model.board.ordered(on: display).first, case .action(let index) = item.id,
            model.actions[index]?.offersUndo == true
        else { return nil }
        return item.id
    }
}

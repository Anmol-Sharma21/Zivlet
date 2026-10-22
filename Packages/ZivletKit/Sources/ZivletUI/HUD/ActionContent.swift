import SwiftUI
import ZivletActions

/// An action result without a surface: the toast, the card with up to five lines, the undo reply and the buttons.
/// `ActionHUDView` puts it on the glass panel; the notch island on its black card.
struct ActionContent: View {
    static let maxLines = 5

    let model: ActionHUDModel
    /// The width of the content itself, inside the surface's padding.
    let width: CGFloat
    var undo: () -> Void = {}
    var details: () -> Void = {}
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let result = model.result {
                if let toast = result.toast { Text(toast).font(.headline).lineLimit(1) }
                if let card = result.card { cardView(card, isAlone: result.toast == nil) }
                if let message = model.undoMessage {
                    Text(message).font(.caption).foregroundStyle(HUDInk.secondary).lineLimit(3)
                }
                buttons(result)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func cardView(_ card: ActionCard, isAlone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title).font(isAlone ? .headline : .callout).lineLimit(3)
            ForEach(Array(card.lines.prefix(Self.maxLines).enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption).foregroundStyle(HUDInk.secondary).lineLimit(1).truncationMode(.middle)
            }
            if card.lines.count > Self.maxLines {
                Text("and \(card.lines.count - Self.maxLines) more").font(.caption).foregroundStyle(HUDInk.secondary)
            }
            if model.showsDetail, let detail = card.detail {
                Text(detail).font(.caption).foregroundStyle(HUDInk.secondary).textSelection(.enabled)
            }
        }
    }

    private func buttons(_ result: ActionResult) -> some View {
        HStack {
            Spacer()
            if model.offersUndo { Button("Undo", action: undo) }
            if result.card?.detail != nil, !model.showsDetail { Button("Show details", action: details) }
            if result.card != nil { Button("Close", action: close).keyboardShortcut(.cancelAction) }
        }
        .controlSize(.small)
    }
}

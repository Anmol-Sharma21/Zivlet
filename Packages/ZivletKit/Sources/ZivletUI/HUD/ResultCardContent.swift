import AppKit
import SwiftUI
import ZivletActions

/// The finished batch's card content (P1-41) without a surface: thumbnail (a drag source for every output), title,
/// sizes, notes, the undo reply, and the buttons the model offers. `ResultCard` puts it on today's glass panel; the
/// notch island puts it on its black card (design/19 §7).
struct ResultCardContent: View {
    let model: ResultCardModel
    let state: CardState
    /// The width of the content itself, inside the surface's padding.
    let width: CGFloat
    /// A drag of the thumbnail began (true) or ended (false); the island holds while it runs (D-N13).
    var onDrag: (Bool) -> Void = { _ in }
    let act: (ResultCardModel.Button) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let first = state.remaining(model.outputs).first { thumbnail(first) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(model.sizeLine ?? model.subtitle).font(.callout).foregroundStyle(HUDInk.secondary).lineLimit(2)
                        .truncationMode(.middle)
                    ForEach(model.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(HUDInk.secondary) }
                    if let message = state.undoMessage {
                        Text(message).font(.caption).foregroundStyle(HUDInk.secondary).lineLimit(3)
                    }
                }
            }
            if state.showsDetails, let details = model.details { detailsView(details) }
            buttons
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// The technical detail (an exit status and the helper's last lines), selectable for a bug report.
    private func detailsView(_ details: String) -> some View {
        ScrollView {
            Text(details).font(.caption.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .padding(6)
        .background(.quaternary, in: .rect(cornerRadius: 6))
    }

    private func thumbnail(_ url: URL) -> some View {
        let image = state.thumbnail ?? ThumbnailLoader.placeholder(for: url)
        return FileDragSource(urls: state.remaining(model.outputs), image: image, onDrag: onDrag)
            .frame(width: ThumbnailLoader.side * 0.75, height: ThumbnailLoader.side * 0.75)
            .accessibilityLabel("Result file. Drag it to use it elsewhere.")
    }

    private var buttons: some View {
        HStack {
            Spacer()
            ForEach(visibleButtons, id: \.self) { button in
                Button(Self.title(button)) { act(button) }
                    .keyboardShortcut(button == .close ? .cancelAction : nil)
            }
        }
        .controlSize(.small)
    }

    private var visibleButtons: [ResultCardModel.Button] { state.visible(model) }

    static func title(_ button: ResultCardModel.Button) -> String {
        switch button {
        case .undo: "Undo"
        case .reveal: "Reveal"
        case .open: "Open"
        case .copy: "Copy"
        case .showDetails: "Show Details"
        case .retry: "Retry"
        case .close: "Close"
        }
    }
}

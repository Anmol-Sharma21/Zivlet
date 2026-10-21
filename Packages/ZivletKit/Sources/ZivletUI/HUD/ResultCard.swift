import AppKit
import SwiftUI

/// The finished batch's card (P1-41): thumbnail (a drag source for every output), title, sizes, notes, the undo
/// reply, and the buttons the model offers.
struct ResultCard: View {
    let model: ResultCardModel
    let state: CardState
    let act: (ResultCardModel.Button) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let first = model.outputs.first { thumbnail(first) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(model.sizeLine ?? model.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .truncationMode(.middle)
                    ForEach(model.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    if let message = state.undoMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
            if state.showsDetails, let details = model.details { detailsView(details) }
            buttons
        }
        .padding(14)
        .frame(width: HUDLayout.size.width, alignment: .topLeading)
        .frame(minHeight: HUDLayout.size.height, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
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
        return FileDragSource(urls: model.outputs, image: image)
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

    /// Undo goes once it has answered, unless the Trash refused something.
    private var visibleButtons: [ResultCardModel.Button] {
        model.buttons.filter { button in
            switch button {
            case .undo: state.undoMessage == nil || state.undoCanRetry
            case .showDetails: !state.showsDetails
            default: true
            }
        }
    }

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

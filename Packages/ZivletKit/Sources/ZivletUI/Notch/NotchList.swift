import SwiftUI
import ZivletNotchCore

/// The expanded list when a display has several items (design/19 §4.3): failed rows first, each with its own ring
/// or result and its own buttons; at most five rows, then "+2 more".
struct NotchList: View {
    let model: NotchHUDModel
    let display: UInt32
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.board.rows(on: display)) { row in
                NotchListRow(row: row, offersUndo: offersUndo(row.id), act: act)
            }
            if let more = model.board.moreLabel(on: display) {
                Text(more).font(.caption).foregroundStyle(NotchInk.secondary)
            }
        }
        .padding(.horizontal, NotchCard.sideInset)
        .padding(.vertical, NotchCard.verticalInset)
        .frame(width: IslandLayout.Metrics.expandedWidth, alignment: .topLeading)
    }

    private func offersUndo(_ id: NotchHUDItemID) -> Bool {
        guard case .action(let index) = id else { return false }
        return model.actions[index]?.offersUndo == true
    }
}

/// One row: its glyph, title and detail, and the buttons its state offers.
struct NotchListRow: View {
    let row: NotchHUDRow
    let offersUndo: Bool
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            glyph
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.callout.weight(.semibold)).foregroundStyle(NotchInk.primary).lineLimit(1)
                    .truncationMode(.middle)
                if !row.detail.isEmpty {
                    Text(row.detail).font(.caption).foregroundStyle(NotchInk.secondary).lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            ForEach(presses, id: \.self) { press in
                Button(Self.title(press)) { act(press, row.id) }
            }
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var glyph: some View {
        switch row.status {
        case .working(let fraction?): NotchRing(fraction: fraction)
        case .working(nil): NotchSteps(step: 0)
        case .saved: NotchSymbol(name: NotchSymbol.saved)
        case .failed: NotchSymbol(name: NotchSymbol.failed)
        case .action: NotchSymbol(name: NotchSymbol.saved)
        }
    }

    /// Working: Cancel. Saved: Reveal and Open. A failed batch: Retry and Close; a failed action: Close. An action
    /// with Undo: Undo.
    private var presses: [NotchHUD.Press] {
        switch (row.status, row.id) {
        case (.working, _): [.cancel]
        case (.saved, _): [.reveal, .open]
        case (.failed, .batch): [.retry, .close]
        case (.failed, .action): [.close]
        case (.action, _): offersUndo ? [.undo] : []
        }
    }

    static func title(_ press: NotchHUD.Press) -> String {
        switch press {
        case .cancel: "Cancel"
        case .undo: ResultCardContent.title(.undo)
        case .reveal: ResultCardContent.title(.reveal)
        case .open: ResultCardContent.title(.open)
        case .copy: ResultCardContent.title(.copy)
        case .showDetails: ResultCardContent.title(.showDetails)
        case .retry: ResultCardContent.title(.retry)
        case .close: ResultCardContent.title(.close)
        }
    }
}

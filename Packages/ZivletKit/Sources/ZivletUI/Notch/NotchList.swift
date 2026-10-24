import SwiftUI
import ZivletNotchCore

/// The expanded list when a display has several items (19b §5): failed rows first, one line each (glyph, the row's
/// line, its short status, its icon buttons); at most five rows, then "+2 more" as a caption.
struct NotchList: View {
    let model: NotchHUDModel
    let display: UInt32
    let underHousing: Bool
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLook.Spacing.s) {
            ForEach(model.board.rows(on: display)) { row in
                NotchListRow(row: row, offersUndo: offersUndo(row.id), act: act)
            }
            if let more = model.board.moreLabel(on: display) { NotchCaption(text: more) }
        }
        .frame(width: NotchCard.contentWidth, alignment: .topLeading)
        .padding(.top, NotchCard.topInset(underHousing: underHousing))
        .padding(.bottom, NotchCard.bottomInset)
        .frame(maxWidth: .infinity)
    }

    private func offersUndo(_ id: NotchHUDItemID) -> Bool {
        guard case .action(let index) = id else { return false }
        return model.actions[index]?.offersUndo == true
    }
}

/// One row on one line: its ring or glyph, its line (gives way), its short status and the buttons its state offers.
struct NotchListRow: View {
    let row: NotchHUDRow
    let offersUndo: Bool
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        HStack(spacing: NotchLook.Spacing.s) {
            glyph
            Text(row.line).font(NotchLook.TypeStyle.primary).foregroundStyle(NotchInk.primary).lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: NotchLook.Spacing.xs)
            if !row.summary.isEmpty {
                Text(row.summary).font(NotchLook.TypeStyle.secondary).foregroundStyle(NotchInk.secondary).lineLimit(1)
                    .fixedSize()
            }
            HStack(spacing: NotchLook.Spacing.xs) {
                ForEach(Self.presses(row, offersUndo: offersUndo), id: \.self) { press in
                    NotchIconButton(press: press) { act(press, row.id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var glyph: some View {
        switch row.status {
        case .working(let fraction?): NotchRing(fraction: fraction)
        case .working(nil): NotchSteps(step: 0)
        case .saved, .action: NotchSymbol(name: NotchSymbol.saved)
        case .failed: NotchSymbol(name: NotchSymbol.failed)
        case .cancelled: NotchSymbol(name: NotchSymbol.cancelled)
        }
    }

    /// Working: Cancel. Saved: Reveal and Open. A failed batch: Retry and Close; a failed action or a cancelled
    /// batch: Close. An action with Undo: Undo.
    static func presses(_ row: NotchHUDRow, offersUndo: Bool) -> [NotchHUD.Press] {
        switch (row.status, row.id) {
        case (.working, _): [.cancel]
        case (.saved, _): [.reveal, .open]
        case (.failed, .batch): [.retry, .close]
        case (.failed, .action), (.cancelled, _): [.close]
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

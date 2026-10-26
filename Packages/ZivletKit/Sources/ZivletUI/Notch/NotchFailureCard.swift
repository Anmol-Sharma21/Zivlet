import SwiftUI
import ZivletActions
import ZivletNotch
import ZivletRuntime

/// The island's failure card (19b §5): the triangle, the reason (up to two lines) over the file name, the details box
/// when shown, and Show Details, Retry and Close as icon buttons. Close keeps Escape (`.cancelAction`). A batch whose
/// jobs were all cancelled uses the same card with the neutral stop glyph, "Cancelled / Nothing was saved." and Close.
struct NotchFailureCard: View {
    let model: ResultCardModel
    let state: CardState
    let width: CGFloat
    let act: (ResultCardModel.Button) -> Void

    var body: some View {
        let lines = Self.lines(model)
        VStack(alignment: .leading, spacing: NotchLook.Spacing.s) {
            HStack(alignment: .bottom, spacing: NotchLook.Spacing.s) {
                HStack(alignment: .top, spacing: NotchLook.Spacing.s) {
                    NotchSymbol(name: Self.glyph(model))
                    VStack(alignment: .leading, spacing: NotchLook.Spacing.xs) {
                        Text(lines.primary).font(NotchLook.TypeStyle.primary).foregroundStyle(NotchInk.primary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if !lines.secondary.isEmpty {
                            Text(lines.secondary).font(NotchLook.TypeStyle.secondary)
                                .foregroundStyle(NotchInk.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        ForEach(model.notes, id: \.self) { NotchCaption(text: $0) }
                        if let message = state.undoMessage { NotchCaption(text: message) }
                    }
                }
                .layoutPriority(1)  // the text takes its width before the button row's spacer
                NotchButtonRow(presses: Self.presses(model, state: state)) { act(Self.button($0)) }
            }
            if state.showsDetails, let details = model.details { NotchDetailsBox(details: details) }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// The triangle for a failure; the neutral stop glyph for a cancelled batch.
    static func glyph(_ model: ResultCardModel) -> String {
        model.phase == .cancelled ? NotchSymbol.cancelled : NotchSymbol.failed
    }

    /// The reason first, the file name second (`BatchPresentation`'s title and subtitle).
    static func lines(_ model: ResultCardModel) -> (primary: String, secondary: String) {
        (model.title, model.subtitle)
    }

    static func presses(_ model: ResultCardModel, state: CardState) -> [NotchHUD.Press] {
        state.visible(model).map(NotchHUD.Press.init)
    }

    private static func button(_ press: NotchHUD.Press) -> ResultCardModel.Button {
        switch press {
        case .undo: .undo
        case .reveal: .reveal
        case .open: .open
        case .copy: .copy
        case .showDetails: .showDetails
        case .retry: .retry
        case .close, .cancel: .close
        }
    }
}

/// The island's card for an action that partly or wholly failed: its glyph, title, up to five caption lines and
/// "and 2 more", the detail when shown, and Undo, Show Details and Close as icon buttons.
struct NotchActionCard: View {
    let model: ActionHUDModel
    let width: CGFloat
    let act: (NotchHUD.Press) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLook.Spacing.s) {
            if let result = model.result {
                HStack(alignment: .bottom, spacing: NotchLook.Spacing.s) {
                    text(result).layoutPriority(1)
                    NotchButtonRow(presses: Self.presses(model), act: act)
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func text(_ result: ActionResult) -> some View {
        HStack(alignment: .top, spacing: NotchLook.Spacing.s) {
            NotchSymbol(name: result.card == nil ? NotchSymbol.saved : NotchSymbol.failed)
            VStack(alignment: .leading, spacing: NotchLook.Spacing.xs) {
                Text(Self.title(result)).font(NotchLook.TypeStyle.primary).foregroundStyle(NotchInk.primary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(Self.lines(result).enumerated()), id: \.offset) { _, line in
                    Text(line).font(NotchLook.TypeStyle.secondary).foregroundStyle(NotchInk.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if model.showsDetail, let detail = result.card?.detail {
                    NotchCaption(text: detail).textSelection(.enabled)
                }
                if let message = model.undoMessage { NotchCaption(text: message) }
            }
        }
    }

    static func title(_ result: ActionResult) -> String { result.card?.title ?? result.toast ?? "" }

    /// Up to five of the card's lines, then "and 2 more" (the M5a words).
    static func lines(_ result: ActionResult) -> [String] {
        guard let card = result.card else { return [] }
        let shown = Array(card.lines.prefix(ActionContent.maxLines))
        let hidden = card.lines.count - shown.count
        return hidden > 0 ? shown + ["and \(hidden) more"] : shown
    }

    static func presses(_ model: ActionHUDModel) -> [NotchHUD.Press] {
        guard let result = model.result else { return [] }
        var presses: [NotchHUD.Press] = []
        if model.offersUndo { presses.append(.undo) }
        if result.card?.detail != nil, !model.showsDetail { presses.append(.showDetails) }
        if result.card != nil { presses.append(.close) }
        return presses
    }
}

/// Icon buttons right-aligned in a row; Close answers Escape.
struct NotchButtonRow: View {
    let presses: [NotchHUD.Press]
    let act: (NotchHUD.Press) -> Void

    var body: some View {
        HStack(spacing: NotchLook.Spacing.xs) {
            Spacer(minLength: 0)
            ForEach(presses, id: \.self) { press in
                NotchIconButton(press: press) { act(press) }
                    .keyboardShortcut(Self.shortcut(press))
            }
        }
    }

    /// Close answers Escape, as in M5a; no other press has a shortcut.
    static func shortcut(_ press: NotchHUD.Press) -> KeyboardShortcut? { press == .close ? .cancelAction : nil }
}

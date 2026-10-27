import SwiftUI
import ZivletNotch
import ZivletNotchCore

/// The toast row (19b §5, D-NL7, D-NL8): the check mark, the error glyph, the action's glyph or a working action's
/// ring, a primary line and a secondary one in two styles (no separator), and Undo or Cancel as an icon button when
/// the item offers it. The primary line gives way first; the secondary line keeps its width. VoiceOver reads the
/// board's spoken form.
struct NotchToast: View {
    let model: NotchHUDModel
    let display: UInt32
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        HStack(spacing: NotchLook.Spacing.s) {
            if let glyph = model.board.toastGlyph(on: display) {
                if glyph == .working, let ring = model.board.tab(on: display)?.ring {
                    NotchRingGlyph(ring: ring).accessibilityHidden(true)  // the line says what it waits for
                } else {
                    Image(systemName: NotchSymbol.name(for: glyph)).font(NotchLook.Symbol.toast)
                        .foregroundStyle(NotchInk.primary).accessibilityHidden(true)  // the line says saved or failed
                }
            }
            if let line = model.board.toastStyledLine(on: display) {
                HStack(spacing: NotchLook.Spacing.s) {
                    PartedLine(parts: line.primary).font(NotchLook.TypeStyle.primary).foregroundStyle(NotchInk.primary)
                        .layoutPriority(line.secondaryGivesWay ? 1 : 0)
                    if let secondary = line.secondary {
                        Text(secondary).font(NotchLook.TypeStyle.secondary).foregroundStyle(NotchInk.secondary)
                            .lineLimit(1).truncationMode(.middle).layoutPriority(line.secondaryGivesWay ? 0 : 1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.board.toastAccessibilityLabel(on: display) ?? line.joined)
            }
            Spacer(minLength: 0)
            if let id = undoable { NotchIconButton(press: .undo) { act(.undo, id) } }
            if let id = cancellable { NotchIconButton(press: .cancel) { act(.cancel, id) } }
        }
        .padding(.horizontal, NotchLook.Spacing.m)
        .frame(maxWidth: .infinity)
        .frame(height: NotchLook.Spacing.rowHeight)
    }

    /// The toast's action, while it works and can be stopped.
    private var cancellable: NotchHUDItemID? {
        guard let item = model.board.ordered(on: display).first, case .action = item.id, item.isWorking else {
            return nil
        }
        return item.id
    }

    /// The toast's action, when it offers Undo now.
    private var undoable: NotchHUDItemID? {
        guard let item = model.board.ordered(on: display).first, case .action(let index) = item.id,
            model.actions[index]?.offersUndo == true
        else { return nil }
        return item.id
    }
}

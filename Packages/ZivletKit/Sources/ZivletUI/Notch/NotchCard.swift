import SwiftUI
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime

/// The expanded island (design/19 §4.3): one item's card, or the list when the display has several. The chrome adds
/// the housing height above it on a notch display and scrolls it past the 320 pt cap.
struct NotchExpanded: View {
    let model: NotchHUDModel
    let display: UInt32
    /// The card hangs below a camera housing (a notch display), not in a pill.
    let underHousing: Bool
    /// A drag of the result thumbnail began or ended.
    let drag: (Bool) -> Void
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        let items = model.board.ordered(on: display)
        if items.count == 1, let item = items.first {
            NotchCard(model: model, item: item, underHousing: underHousing, drag: drag, act: act)
        } else {
            NotchList(model: model, display: display, underHousing: underHousing, act: act)
        }
    }
}

/// One item's card inside the island's body (19b §3.1, §5): 8 pt below the housing (12 pt from the top of a pill),
/// 16 pt from the body's sides (after the 6 pt flare), 12 pt above the bottom edge, so content is concentric with the
/// 24 pt corners.
struct NotchCard: View {
    static let sideInset = NotchLook.Spacing.l
    static let bottomInset = NotchLook.Spacing.m

    /// Below a housing its black band already sits above the content; a pill gets the bottom's inset at the top too.
    static func topInset(underHousing: Bool) -> CGFloat { underHousing ? NotchLook.Spacing.s : bottomInset }

    static let contentWidth = IslandLayout.Metrics.expandedWidth - 2 * IslandLook.flare - 2 * sideInset

    let model: NotchHUDModel
    let item: NotchHUDItem
    let underHousing: Bool
    let drag: (Bool) -> Void
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        content.frame(width: Self.contentWidth, alignment: .topLeading)
            .padding(.top, Self.topInset(underHousing: underHousing)).padding(.bottom, Self.bottomInset)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        let id = item.id
        switch item.kind {
        case .batch(let snapshot) where !snapshot.isFinished:
            NotchWorkingCard(snapshot: snapshot) { act(.cancel, id) }
        case .batch(let snapshot) where !snapshot.outputs.isEmpty:
            if let state = model.cards[snapshot.batch] {
                NotchResultCard(
                    model: ResultCardModel(snapshot), state: state, width: Self.contentWidth, onDrag: drag
                ) {
                    act(NotchHUD.Press($0), id)
                }
            }
        case .batch(let snapshot):
            if let state = model.cards[snapshot.batch] {
                NotchFailureCard(model: ResultCardModel(snapshot), state: state, width: Self.contentWidth) {
                    act(NotchHUD.Press($0), id)
                }
            }
        case .action:
            if case .action(let index) = id, let action = model.actions[index] {
                NotchActionCard(model: action, width: Self.contentWidth) { act($0, id) }
            }
        }
    }
}

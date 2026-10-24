import SwiftUI
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime

/// The expanded island (design/19 §4.3): one item's card, or the list when the display has several. The chrome adds
/// the housing height above it on a notch display and scrolls it past the 320 pt cap.
struct NotchExpanded: View {
    let model: NotchHUDModel
    let display: UInt32
    /// A drag of the result thumbnail began or ended.
    let drag: (Bool) -> Void
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        let items = model.board.ordered(on: display)
        if items.count == 1, let item = items.first {
            NotchCard(model: model, item: item, drag: drag, act: act)
        } else {
            NotchList(model: model, display: display, act: act)
        }
    }
}

/// One item's card inside the island's body (19b §3.1, §5): 8 pt below the housing, 16 pt from the body's sides
/// (after the 6 pt flare), 12 pt above the bottom edge, so content is concentric with the 24 pt corners.
struct NotchCard: View {
    static let sideInset = NotchLook.Spacing.l
    static let topInset = NotchLook.Spacing.s
    static let bottomInset = NotchLook.Spacing.m
    static let contentWidth = IslandLayout.Metrics.expandedWidth - 2 * IslandLook.flare - 2 * sideInset

    let model: NotchHUDModel
    let item: NotchHUDItem
    let drag: (Bool) -> Void
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        content.frame(width: Self.contentWidth, alignment: .topLeading)
            .padding(.top, Self.topInset).padding(.bottom, Self.bottomInset)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        let id = item.id
        switch item.kind {
        case .batch(let snapshot) where !snapshot.isFinished:
            NotchWorkingCard(snapshot: snapshot) { act(.cancel, id) }
        case .batch(let snapshot) where snapshot.failures.isEmpty:
            if let state = model.cards[snapshot.batch] {
                NotchResultCard(
                    model: ResultCardModel(snapshot), state: state, width: Self.contentWidth, onDrag: drag
                ) {
                    act(NotchHUD.Press($0), id)
                }
            }
        case .batch(let snapshot):
            if let state = model.cards[snapshot.batch] {
                ResultCardContent(
                    model: ResultCardModel(snapshot), state: state, width: Self.contentWidth, onDrag: drag
                ) {
                    act(NotchHUD.Press($0), id)
                }
            }
        case .action:
            if case .action(let index) = id, let action = model.actions[index] {
                ActionContent(
                    model: action, width: Self.contentWidth, undo: { act(.undo, id) },
                    details: { act(.showDetails, id) }, close: { act(.close, id) })
            }
        }
    }
}

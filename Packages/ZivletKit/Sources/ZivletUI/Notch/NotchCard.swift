import SwiftUI
import ZivletNotchCore
import ZivletRuntime

/// The expanded island (design/19 §4.3): one item's card, or the list when the display has several. The chrome adds
/// the housing height above it on a notch display and scrolls it past the 320 pt cap.
struct NotchExpanded: View {
    let model: NotchHUDModel
    let display: UInt32
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        let items = model.board.ordered(on: display)
        if items.count == 1, let item = items.first {
            NotchCard(model: model, item: item, act: act)
        } else {
            NotchList(model: model, display: display, act: act)
        }
    }
}

/// One item's card: today's working view, result card or action card at the glass card's content width, centred in
/// the 380 pt island (D-N10). The 24 pt sides keep the buttons clear of the 22 pt bottom corners.
struct NotchCard: View {
    static let contentWidth = HUDLayout.contentWidth
    static let sideInset = (IslandLayout.Metrics.expandedWidth - contentWidth) / 2
    static let verticalInset = HUDLayout.padding

    let model: NotchHUDModel
    let item: NotchHUDItem
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void

    var body: some View {
        content.padding(.horizontal, Self.sideInset).padding(.vertical, Self.verticalInset)
    }

    @ViewBuilder private var content: some View {
        let id = item.id
        switch item.kind {
        case .batch(let snapshot) where !snapshot.isFinished:
            WorkingContent(snapshot: snapshot, width: Self.contentWidth) { act(.cancel, id) }
        case .batch(let snapshot):
            if let state = model.cards[snapshot.batch] {
                ResultCardContent(model: ResultCardModel(snapshot), state: state, width: Self.contentWidth) {
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

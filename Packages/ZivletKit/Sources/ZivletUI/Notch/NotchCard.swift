import SwiftUI
import ZivletActions
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
    var text: (TextResultButton, NotchHUDItemID) -> Void = { _, _ in }

    var body: some View {
        let items = model.board.ordered(on: display)
        if items.count == 1, let item = items.first {
            NotchCard(model: model, item: item, underHousing: underHousing, drag: drag, act: act, text: text)
        } else {
            NotchList(model: model, display: display, underHousing: underHousing, act: act)
        }
    }
}

/// One item's card inside the island's body (19b §3.1, §5): 8 pt below the housing (12 pt from the top of a pill),
/// 16 pt from the body's sides (after the 6 pt flare on a notch display), 12 pt above the bottom edge, so content is
/// concentric with the 24 pt corners.
struct NotchCard: View {
    static let sideInset = NotchLook.Spacing.l
    static let bottomInset = NotchLook.Spacing.m

    /// Below a housing its black band already sits above the content; a pill gets the bottom's inset at the top too.
    static func topInset(underHousing: Bool) -> CGFloat { underHousing ? NotchLook.Spacing.s : bottomInset }

    /// The body's width less the card's insets: under a housing the body is the frame less the two flares; the pill
    /// has no flare, so its content is 16 pt from the body's sides too.
    static func contentWidth(underHousing: Bool) -> CGFloat {
        let flare = underHousing ? IslandLook.flare : 0
        return IslandLayout.Metrics.expandedWidth - 2 * flare - 2 * sideInset
    }

    private var contentWidth: CGFloat { Self.contentWidth(underHousing: underHousing) }

    let model: NotchHUDModel
    let item: NotchHUDItem
    let underHousing: Bool
    let drag: (Bool) -> Void
    let act: (NotchHUD.Press, NotchHUDItemID) -> Void
    var text: (TextResultButton, NotchHUDItemID) -> Void = { _, _ in }

    var body: some View {
        content.frame(width: contentWidth, alignment: .topLeading)
            .padding(.top, Self.topInset(underHousing: underHousing)).padding(.bottom, Self.bottomInset)
            .frame(maxWidth: .infinity)
    }

    /// Which card a batch gets, from its phase: a partly saved batch keeps the result card (DV6); a failure and a
    /// cancelled batch share the failure card's layout with their own glyph.
    enum Face: Equatable { case working, result, failure, cancelled }

    static func face(_ snapshot: BatchSnapshot) -> Face {
        switch BatchPresentation.make(snapshot).phase {
        case .working: .working
        case .succeeded, .partial: .result
        case .failed: .failure
        case .cancelled: .cancelled
        }
    }

    @ViewBuilder private var content: some View {
        let id = item.id
        switch item.kind {
        case .batch(let snapshot):
            batch(snapshot, id: id)
        case .action:
            if case .action(let index) = id, let action = model.actions[index] {
                if let result = action.result, let outcome = result.text {
                    NotchTextCard(
                        toast: result.toast ?? "", model: TextResultModel(outcome), width: contentWidth
                    ) { text($0, id) }
                } else {
                    NotchActionCard(model: action, width: contentWidth) { act($0, id) }
                }
            }
        }
    }

    @ViewBuilder private func batch(_ snapshot: BatchSnapshot, id: NotchHUDItemID) -> some View {
        let face = Self.face(snapshot)
        if face == .working {
            NotchWorkingCard(snapshot: snapshot) { act(.cancel, id) }
        } else if let state = model.cards[snapshot.batch] {
            let press: (ResultCardModel.Button) -> Void = { act(NotchHUD.Press($0), id) }
            if face == .result {
                NotchResultCard(
                    model: ResultCardModel(snapshot), state: state, width: contentWidth, onDrag: drag, act: press)
            } else {
                NotchFailureCard(model: ResultCardModel(snapshot), state: state, width: contentWidth, act: press)
            }
        }
    }
}

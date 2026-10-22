import SwiftUI

/// The finished batch's card on today's glass panel near the drop (P1-41).
struct ResultCard: View {
    let model: ResultCardModel
    let state: CardState
    let act: (ResultCardModel.Button) -> Void

    var body: some View {
        ResultCardContent(model: model, state: state, width: HUDLayout.contentWidth, act: act)
            .padding(HUDLayout.padding)
            .frame(width: HUDLayout.size.width, alignment: .topLeading)
            .frame(minHeight: HUDLayout.size.height, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .hudGlass()
    }
}

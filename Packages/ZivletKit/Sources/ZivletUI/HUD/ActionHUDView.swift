import SwiftUI
import ZivletActions

/// The action HUD on today's glass panel near the drop: `ActionContent` with the panel's padding, width and glass.
struct ActionHUDView: View {
    let model: ActionHUDModel
    var undo: () -> Void = {}
    var details: () -> Void = {}
    var close: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
    var text: (TextResultButton) -> Void = { _ in }

    var body: some View {
        ActionContent(
            model: model, width: ActionHUD.width - 2 * HUDLayout.padding, undo: undo, details: details, close: close,
            text: text
        )
        .padding(HUDLayout.padding)
        .frame(width: ActionHUD.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .hudGlass()
        .onHover(perform: hover)
    }
}

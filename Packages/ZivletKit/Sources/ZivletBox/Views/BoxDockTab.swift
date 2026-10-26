import SwiftUI
import ZivletNotch
import ZivletShelfCore

/// The docked tab (19c §3.3): against its screen edge, rounded only on the inner side, the box symbol over the count;
/// during a drag over it, wider, with the drop symbol. A click opens the panel.
struct BoxDockTab: View {
    let model: BoxViewModel
    let edge: DockEdge
    let press: (BoxPress) -> Void

    private var shape: UnevenRoundedRectangle {
        let r = BoxLook.Tab.radius
        return edge == .right
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
            : UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    var body: some View {
        let size = BoxLayout.size(of: model)
        VStack(spacing: IslandContentLook.Spacing.xs) {
            Image(systemName: model.presentation.acceptsDrop ? BoxSymbols.dropHere : BoxSymbols.box)
                .font(IslandContentLook.Symbol.tab)
            Text("\(model.items.count)")
                .font(IslandContentLook.TypeStyle.count)
                .monospacedDigit()
        }
        .foregroundStyle(IslandInk.primary)
        .frame(width: size.width, height: size.height)
        .background(BoxSurface(finish: model.finish, shape: shape))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { press(.openPanel) }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoxSpeech.header(count: model.items.count, bytes: model.totalBytes))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { press(.openPanel) }
    }
}

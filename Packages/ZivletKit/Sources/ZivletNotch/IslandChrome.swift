import SwiftUI
import ZivletNotchCore

/// What the island draws, set by its host: the shape's rectangle inside the panel (top-left origin), its corners, the
/// client's content for the surface and the accessibility text of the island group.
@Observable
final class IslandChromeModel {
    var panelSize = CGSize(width: 1, height: 1)
    var shapeRect = CGRect.zero
    var opacity = 0.0
    var topRadius = 0.0
    var bottomRadius = IslandLayout.Metrics.collapsedRadius
    /// The housing height on a notch display: content starts below it, never behind the camera.
    var contentTopInset = 0.0
    var scrolls = false
    var surface = IslandSurface.hidden
    var content = AnyView(EmptyView())
    var accessibilityLabel = ""
    var accessibilityValue = ""
    var accessibilityActionName = ""
    var onAccessibilityAction: () -> Void = {}
    var onAccessibilityFocus: (Bool) -> Void = { _ in }
}

/// The black island (D-N10) with the client's content, inside a transparent panel-sized canvas. One accessibility
/// group with a label, a value and the "show" action; accessibility focus entering or leaving reaches the machine.
struct IslandChrome: View {
    let model: IslandChromeModel
    @AccessibilityFocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            island
                .frame(width: model.shapeRect.width, height: model.shapeRect.height)
                .offset(x: model.shapeRect.minX, y: model.shapeRect.minY)
        }
        .frame(width: model.panelSize.width, height: model.panelSize.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    private var shape: IslandShape { IslandShape(top: model.topRadius, bottom: model.bottomRadius) }

    private var island: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if contrast == .increased { shape.stroke(Color.white.opacity(0.5), lineWidth: 1) }
            content
                .padding(.top, model.contentTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(model.surface)
                .transition(.opacity)
        }
        .clipShape(shape)
        .opacity(model.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityAction(named: model.accessibilityActionName) { model.onAccessibilityAction() }
        .accessibilityFocused($focused)
        .onChange(of: focused) { _, now in model.onAccessibilityFocus(now) }
    }

    @ViewBuilder private var content: some View {
        if model.scrolls {
            ScrollView(.vertical) { model.content }
        } else {
            model.content
        }
    }
}

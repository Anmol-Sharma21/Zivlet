import SwiftUI
import ZivletNotchCore

/// What the island draws, set by its host: the shape's rectangle, its corners and the client's content for the
/// surface. The island group's accessibility text lives in `IslandAccessibilityModel`.
@Observable
final class IslandChromeModel {
    var panelSize = CGSize(width: 1, height: 1)
    /// The shape from the panel's top centre: x from the centre line, y down from the top edge. Every surface hangs
    /// from the same centre, so growing or shrinking the panel about it does not move the drawing.
    var shapeRect = CGRect.zero
    var opacity = 0.0
    var topRadius = 0.0
    var bottomRadius = IslandLayout.Metrics.collapsedRadius
    /// The concave curve into the screen edge on a notch display; 0 on the pill (19b D-NL4). Content stays inside
    /// the body, between the two curves.
    var flare = 0.0
    /// The housing height on a notch display: content starts below it, never behind the camera.
    var contentTopInset = 0.0
    var scrolls = false
    var surface = IslandSurface.hidden
    var content = AnyView(EmptyView())
    /// How a new surface's content enters and the old one leaves (19b D-NL13).
    var contentTransition = IslandContentTransition.fade
    /// Black, glass or solid for the shown surface (19b D-NL1 … D-NL3).
    var finish = IslandFinish.black(outline: false)
}

/// The island's finish (19b D-NL1 … D-NL3) with the client's content, inside a transparent panel-sized canvas, as one accessibility
/// group (`IslandAccessibility`).
struct IslandChrome: View {
    let model: IslandChromeModel
    let accessibility: IslandAccessibilityModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
                .frame(width: model.shapeRect.width, height: model.shapeRect.height)
                .offset(x: model.shapeRect.midX, y: model.shapeRect.minY)
        }
        .frame(width: model.panelSize.width, height: model.panelSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var shape: IslandShape { IslandShape(top: model.topRadius, bottom: model.bottomRadius, flare: model.flare) }

    private var island: some View {
        ZStack(alignment: .top) {
            IslandFinishView(finish: model.finish, shape: shape)
            content
                .padding(.top, model.contentTopInset)
                .padding(.horizontal, model.flare)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(model.surface)
                .transition(model.contentTransition.transition)
        }
        .clipShape(shape)
        .opacity(model.opacity)
        .modifier(IslandAccessibility(model: accessibility))
    }

    @ViewBuilder private var content: some View {
        if model.scrolls {
            ScrollView(.vertical) { model.content }
        } else {
            model.content
        }
    }
}

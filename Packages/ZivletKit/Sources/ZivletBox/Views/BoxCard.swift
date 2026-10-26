import SwiftUI
import ZivletNotch

/// The panel's surface (19c D-BL1, D-BL2): the finish in a continuous rounded rectangle, the outline only under
/// Increase Contrast, dark always. The content is laid out at the size `BoxLayout` computed.
struct BoxCard<Content: View>: View {
    let finish: BoxFinish
    let size: CGSize
    @ViewBuilder let content: Content

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: BoxLook.Panel.radius, style: .continuous) }

    var body: some View {
        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BoxSurface(finish: finish, shape: shape))
            .clipShape(shape)
            .environment(\.colorScheme, .dark)
            .environment(\.islandOutlined, finish.outlined)
    }
}

/// A finish in any shape, with the Increase Contrast outline drawn inside its edge.
struct BoxSurface<S: InsettableShape>: View {
    let finish: BoxFinish
    let shape: S

    var body: some View {
        ZStack {
            SurfaceFill(finish: finish.islandFinish, shape: shape)
            if finish.outlined {
                shape.strokeBorder(Color.white.opacity(IslandLook.Outline.opacity), lineWidth: IslandLook.Outline.width)
            }
        }
    }
}

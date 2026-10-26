import SwiftUI
import ZivletNotchCore

/// Draws an `IslandFinish` inside the island's shape (19b D-NL1 … D-NL3): solid black; Liquid Glass under a black
/// scrim; or the solid grey of Reduce Transparency and Increase Contrast. Below a housing the top stays black down to
/// the housing's bottom edge and fades into the finish over `IslandLook.fade`, so the housing and the island read as
/// one piece. The Increase Contrast outline is drawn inside the edge, open along the screen edge on a notch display.
struct IslandFinishView: View {
    let finish: IslandFinish
    let shape: IslandShape

    var body: some View {
        ZStack(alignment: .top) {
            SurfaceFill(finish: finish, shape: shape)
            if finish.outlined {
                IslandOutline(shape: shape, lineWidth: IslandLook.Outline.width)
                    .fill(Color.white.opacity(IslandLook.Outline.opacity))
            }
        }
    }
}

/// The fill of a finish in any shape (19b D-NL1 … D-NL3): black, Liquid Glass under the black scrim, or the solid grey
/// of Reduce Transparency and Increase Contrast, with the housing band on top when there is one. Shared by the island
/// and the Drop Box (plan 16 D-M5b-22); each draws its own outline.
public struct SurfaceFill<S: InsettableShape>: View {
    public let finish: IslandFinish
    public let shape: S

    public init(finish: IslandFinish, shape: S) {
        self.finish = finish
        self.shape = shape
    }

    public var body: some View {
        switch finish {
        case .black:
            shape.fill(Color.black)
        case .glass(let band):
            ZStack(alignment: .top) {
                Color.black.opacity(IslandLook.scrim)
                IslandBand(height: band)
            }
            .clipShape(shape)
            .glassEffect(.regular, in: shape)
        case .solid(let band, _):
            ZStack(alignment: .top) {
                Color(white: IslandLook.solidGrey)
                IslandBand(height: band)
            }
            .clipShape(shape)
        }
    }
}

/// Black from the top edge to `height`, then a fade to clear over `IslandLook.fade`; nothing when `height` is 0.
struct IslandBand: View {
    let height: Double

    var body: some View {
        if height > 0 {
            VStack(spacing: 0) {
                Color.black.frame(height: height)
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: IslandLook.fade)
                Spacer(minLength: 0)
            }
        }
    }
}

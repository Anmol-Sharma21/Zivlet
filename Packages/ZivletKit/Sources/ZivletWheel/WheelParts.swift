import SwiftUI
import ZivletWheelCore

/// Format label (12 pt semibold) or symbol + tool/action label (12.6 pt symbol, 7.5 pt text) (03a §2.2).
struct PetalLabel: View {
    let slice: WheelSlice
    let position: CGPoint
    let colour: Color

    var body: some View {
        content
            .foregroundStyle(colour)
            .multilineTextAlignment(.center)
            .position(position)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        if let symbol = slice.symbolName {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 12.6, weight: .medium))
                Text(slice.label).font(.system(size: 7.5, weight: .semibold)).tracking(0.2)
                    .lineLimit(2).frame(width: 82, height: 22, alignment: .top)
            }
        } else {
            VStack(spacing: 0) {
                Text(slice.label).font(.system(size: 12, weight: .semibold)).tracking(0.35).frame(width: 82, height: 24)
                if let badge = slice.badge { Text(badge).font(.system(size: 7, weight: .medium)).opacity(0.8) }
            }
        }
    }
}

/// Hub text: 10 pt medium for one item, 7 pt semibold for several, shrinking to fit 58 × 28 (03a §2.2).
struct HubLabelView: View {
    let text: String
    let compact: Bool
    let colour: Color

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 7 : 10, weight: compact ? .semibold : .medium))
            .tracking(0.2)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.55)
            .foregroundStyle(colour)
            .frame(width: 58, height: 28)
    }
}

/// Empty-state or reject message: 276 × 58, corner 15, 14 pt medium, two lines (03a §2.2).
struct StatusPill: View {
    let text: String
    let theme: WheelTheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .frame(width: 276, height: 58)
            .background {
                if theme == .solid { shape.fill(Color(white: 0.12)) }
            }
            .foregroundStyle(theme == .solid ? Color.white : Color.primary)
            .glassEffect(theme == .glass ? .regular : .identity, in: shape)
    }
}

/// Horizontal three-cycle shake for a refused wheel switch (03a §2.7).
nonisolated struct ShakeEffect: GeometryEffect {
    var travel: Double = 6
    var shakes: Double = 3
    var animatableData: Double

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 2 * shakes), y: 0))
    }
}

/// Scrim under idle glass petal labels for contrast over any backdrop (01-prd FR-26, ≥ 4.5:1): darker under the
/// white labels of dark mode, lighter under the black labels of light mode. A glass `.tint` this faint barely moves
/// the petal over white windows (measured 2.7:1), so the scrim is drawn as content on the glass.
enum GlassInk {
    static let idleScrimOpacity = 0.4

    static func idleScrim(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.black : Color.white).opacity(idleScrimOpacity)
    }
}

/// Soft drop shadow around the disk (Zivlet wheel spec, 03a §2.2; the panel itself has no shadow, 03a §2.1). It is
/// masked to the outside of the disk so it never darkens the glass.
struct DiskShadow: View {
    static let opacity = 0.32
    static let blur = 10.0
    static let drop = 3.0
    let radius: Double

    var body: some View {
        let disk = Circle().inset(by: WheelLayout.geometry.panelSide / 2 - radius)
        disk.fill(Color.black.opacity(Self.opacity))
            .blur(radius: Self.blur)
            .offset(y: Self.drop)
            .mask(Rectangle().subtracting(disk))
    }
}

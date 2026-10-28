import SwiftUI
import ZivletNotch

/// A slider whose track fills from the centre (P2-30, plan 20b A3, D-M7-11): a white fill at full opacity over the
/// island's track ink, a centre tick and a round thumb. Drag or click to set it; ↑ → and ↓ ← step by 0.05 (⌥ 0.01),
/// Home goes back to neutral. VoiceOver reads the label and the tool's own words for the value, and adjusts it with
/// the same steps. Its first users are the 2B tools (Trim, Speed, Normalize, Edit).
struct BipolarSlider: View {
    static let trackHeight: CGFloat = 4
    static let thumbSide: CGFloat = 14
    static let height: CGFloat = 20

    let label: String
    @Binding var value: BipolarValue
    /// The tool's words for a position ("0.7×", "−3 dB").
    let valueText: (BipolarValue) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
            HStack {
                Text(label).font(IslandContentLook.TypeStyle.primary).foregroundStyle(IslandInk.primary)
                Spacer(minLength: 0)
                Text(valueText(value)).font(IslandContentLook.TypeStyle.secondary).foregroundStyle(IslandInk.secondary)
            }
            .accessibilityHidden(true)
            GeometryReader { proxy in track(width: proxy.size.width) }
                .frame(height: Self.height)
        }
        .focusable()
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow, .home]) { press in
            guard let step = Self.step(for: press.key) else { return .ignored }
            value = value.stepped(step, fine: press.modifiers.contains(.option))
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Self.accessibilityValue(value, valueText: valueText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = value.stepped(.up)
            case .decrement: value = value.stepped(.down)
            @unknown default: break
            }
        }
    }

    private func track(width: CGFloat) -> some View {
        let half = width / 2
        let fill = value.fill
        return ZStack(alignment: .leading) {
            Capsule().fill(IslandInk.track).frame(height: Self.trackHeight)
            Capsule().fill(IslandInk.primary)
                .frame(width: max(0, CGFloat(fill.upperBound - fill.lowerBound) * half), height: Self.trackHeight)
                .offset(x: half + CGFloat(fill.lowerBound) * half)
            Rectangle().fill(IslandInk.secondary).frame(width: 1, height: Self.height / 2).offset(x: half)
            Circle().fill(IslandInk.primary).frame(width: Self.thumbSide, height: Self.thumbSide)
                .offset(x: half + CGFloat(value.position) * (half - Self.thumbSide / 2) - Self.thumbSide / 2)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                value = BipolarValue(Double((drag.location.x - half) / max(half, 1)))
            })
    }

    static func step(for key: KeyEquivalent) -> BipolarValue.Step? {
        switch key {
        case .upArrow, .rightArrow: .up
        case .downArrow, .leftArrow: .down
        case .home: .home
        default: nil
        }
    }

    static func accessibilityValue(_ value: BipolarValue, valueText: (BipolarValue) -> String) -> String {
        valueText(value)
    }
}

import SwiftUI
import ZivletNotch

/// The sheet's choice controls without the system accent (19b D-NL11, OWN-UI-1, D-M7-62): white on the system blue
/// falls under 4.5:1 (3.89:1 measured on the selected Printing segment), so the selected segment is white with black
/// text and the checkboxes draw their mark in white. Every word then holds 4.5:1 on glass and the solid finish.
enum PasswordChoiceLook {
    /// sRGB grey of the selected segment's fill and of its text.
    static let selectedFillGrey = 1.0
    static let selectedInkGrey = 0.0
    static let selectedFill = Color(white: selectedFillGrey)
    static let selectedInk = Color(white: selectedInkGrey)
    /// The segments share the row's width, so the control's edges line up with the sheet's other content.
    static let segmentsFillTheRow = true
    static let cornerRadius = 6.0
    static let inset = 2.0

    /// WCAG contrast of the selected segment's text on its fill.
    static var selectedContrast: Double {
        let (fill, ink) = (IslandInk.luminance(selectedFillGrey), IslandInk.luminance(selectedInkGrey))
        return (max(fill, ink) + 0.05) / (min(fill, ink) + 0.05)
    }
}

/// A segmented choice in the island's ink: the selected segment white with black text, the others white text, inside
/// a hairline in the track's white. VoiceOver reads the group's title, each choice, and which one is selected.
struct PasswordSegmentedChoice<Value: Hashable>: View {
    let title: String
    let choices: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: PasswordChoiceLook.inset) {
            ForEach(choices.indices, id: \.self) { index in segment(choices[index]) }
        }
        .padding(PasswordChoiceLook.inset)
        .overlay {
            RoundedRectangle(
                cornerRadius: PasswordChoiceLook.cornerRadius + PasswordChoiceLook.inset, style: .continuous
            )
            .strokeBorder(IslandInk.track, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func segment(_ choice: (value: Value, label: String)) -> some View {
        let selected = choice.value == selection
        return Button {
            selection = choice.value
        } label: {
            Text(choice.label)
                .font(IslandContentLook.TypeStyle.secondary)
                .foregroundStyle(selected ? PasswordChoiceLook.selectedInk : IslandInk.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: PasswordChoiceLook.cornerRadius, style: .continuous)
                        .fill(selected ? PasswordChoiceLook.selectedFill : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A checkbox drawn in the island's white: a square, filled with its check cut out when on.
struct PasswordCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: IslandContentLook.Spacing.s) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(IslandInk.primary)
                    .accessibilityHidden(true)
                configuration.label
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

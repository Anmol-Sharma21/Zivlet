import SwiftUI
import ZivletNotch

/// An editable timecode (P2-30, plan 20b A3, D-M7-11): a text field that takes `1:30`, `0:01:30.5` and the like,
/// shows the error sentence under it while what was typed is not a valid time, and keeps the last valid value in the
/// binding. VoiceOver reads the label, the value and the error.
struct TimecodeField: View {
    let label: String
    @Binding var value: Duration
    let limit: Duration?
    @State private var entry: TimecodeEntry?

    init(label: String, value: Binding<Duration>, limit: Duration?) {
        self.label = label
        _value = value
        self.limit = limit
    }

    private var current: TimecodeEntry { entry ?? TimecodeEntry(value: value, limit: limit) }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
            HStack(spacing: IslandContentLook.Spacing.s) {
                Text(label).font(IslandContentLook.TypeStyle.primary).foregroundStyle(IslandInk.primary)
                    .accessibilityHidden(true)
                TextField(label, text: Binding(get: { current.text }, set: edit))
                    .textFieldStyle(.roundedBorder)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .accessibilityLabel(label)
                    .accessibilityHint(current.error?.message ?? "")
            }
            if let error = current.error {
                Text(error.message)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func edit(_ text: String) {
        let next = current.edited(text)
        entry = next
        if next.error == nil { value = next.value }
    }
}

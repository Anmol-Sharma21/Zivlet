import SwiftUI
import ZivletCore
import ZivletTrigger

/// One wheel's key: a picker over the four modifiers; a key in use elsewhere swaps (`BindingEditing`).
struct BindingPicker: View {
    let mode: WheelMode
    let model: SettingsModel

    var body: some View {
        Picker(Self.title(mode), selection: model.modifierBinding(for: mode)) {
            ForEach(BindingEditing.choices) { choice in Text(choice.title).tag(choice.mask.rawValue) }
        }
    }

    static func title(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: "Convert wheel"
        case .tools: "Tools wheel"
        case .actions: "Actions wheel"
        }
    }
}

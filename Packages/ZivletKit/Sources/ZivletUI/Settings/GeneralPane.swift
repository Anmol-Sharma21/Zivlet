import SwiftUI
import ZivletActions
import ZivletCore
import ZivletSettings

/// General (03b §8.1): wheel keys, feedback, results and the terminal.
struct GeneralPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(WheelMode.allCases, id: \.self) { BindingPicker(mode: $0, model: model) }
            } header: {
                Text("Wheel keys")
            } footer: {
                Text("Tap the key while dragging files to open that wheel. Each wheel needs its own key.")
                    .foregroundStyle(.secondary)
            }
            Section("Feedback") {
                Toggle("Play a tick when a slice lights up", isOn: model.binding(\.feedback.sound))
                Toggle("Trackpad haptics", isOn: model.binding(\.feedback.haptics))
                Picker("Wheel style", selection: model.binding(\.feedback.theme)) {
                    Text("Glass").tag(ThemeChoice.glass)
                    Text("Solid").tag(ThemeChoice.solid)
                }
                .pickerStyle(.segmented)
            }
            Section("Results") {
                Toggle("Show results in Finder", isOn: model.binding(\.output.revealResults))
                LabeledContent("If the original folder is read-only, save to") {
                    HStack {
                        Text(Self.folderName(model.settings.output.fallbackFolder)).lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: model.commands.chooseFallbackFolder)
                    }
                }
            }
            Section("Actions") {
                Picker("Open folders in", selection: model.binding(\.actions.terminal)) {
                    ForEach(model.terminalChoices) { Text($0.name).tag($0.id) }
                }
            }
        }
    }

    /// "~/Downloads" style: the home folder shortened.
    static func folderName(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

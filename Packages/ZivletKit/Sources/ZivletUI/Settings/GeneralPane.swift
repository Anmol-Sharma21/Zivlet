import SwiftUI
import ZivletActions
import ZivletCore
import ZivletSettings

/// General (03b §8.1): wheel keys, feedback, results and the terminal.
struct GeneralPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            if let login = model.loginItem { LoginItemSection(model: login) }
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
            PlacementSection(model: model)
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

/// Where progress and results show (design/19 §6): the picker shows the resolved value; a choice is stored.
struct PlacementSection: View {
    let model: SettingsModel

    var body: some View {
        Section(PlacementCopy.section) {
            Picker(
                PlacementCopy.title,
                selection: Binding(get: { model.shownPlacement }, set: { model.choosePlacement($0) })
            ) {
                Text(model.notchLabel).tag(HUDPlacement.notch)
                Text(PlacementCopy.nearDropLabel).tag(HUDPlacement.nearDrop)
            }
        }
    }
}

/// "Open Zivlet at login", with the approval hint and any refusal underneath.
struct LoginItemSection: View {
    let model: LoginItemModel

    var body: some View {
        Section("Startup") {
            Toggle("Open Zivlet at login", isOn: Binding(get: { model.isOn }, set: { model.setOn($0) }))
            if let approval = model.approvalMessage {
                HStack {
                    Text(approval).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items", action: model.openSystemSettings)
                }
            }
            if let error = model.errorText { Text(error).foregroundStyle(.red) }
        }
    }
}

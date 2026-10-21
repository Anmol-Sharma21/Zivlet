import SwiftUI
import ZivletEngineKit
import ZivletSettings

/// Updates (03b §8.1, 14 §6): Sparkle's two switches, Check Now and the channel. Until the feed and key exist the
/// updater does not run (D-M4-11), so Check Now is disabled and says why.
struct UpdatesPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: model.binding(\.updates.automaticChecks))
                Toggle("Download and install updates automatically", isOn: model.binding(\.updates.automaticDownloads))
                    .disabled(!model.settings.updates.automaticChecks)
                LabeledContent("Channel", value: "Stable")
            }
            Section {
                HStack {
                    Button("Check Now") { model.commands.checkForUpdates?() }
                        .disabled(model.commands.checkForUpdates == nil)
                    if model.commands.checkForUpdates == nil {
                        Text("Updates aren't set up in this build.").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

import SwiftUI
import ZivletEngineKit
import ZivletSettings

/// Advanced (03b §8.1): the helper versions, diagnostics and the acknowledgements.
struct AdvancedPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("Helpers") {
                ForEach(model.helperVersions, id: \.name) { helper in
                    LabeledContent(helper.name, value: helper.version ?? "Not found")
                }
                if model.helperVersions.isEmpty { Text("Checking…").foregroundStyle(.secondary) }
            }
            Section {
                if let copy = model.commands.copyDiagnostics { Button("Copy Diagnostics", action: copy) }
                Button("Acknowledgements…") { model.commands.openAcknowledgements?() }
                    .disabled(model.commands.openAcknowledgements == nil)
            }
        }
    }
}

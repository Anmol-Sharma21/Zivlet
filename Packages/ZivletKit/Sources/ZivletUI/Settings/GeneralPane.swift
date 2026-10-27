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
            TextRecognitionSection(model: model)
            PlacementSection(model: model)
            DropBoxSection(model: model)
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

/// The Drop Box group (19c §5, D-M5b-19): the tray while dragging, shake to open, auto-clear and where new drops go.
struct DropBoxSection: View {
    static let title = "Drop Box"
    static let trayLabel = "Open at the notch while dragging"
    static let shakeLabel = "Shake to open"
    static let clearLabel = "Clear items"
    /// Only the BOX slice chooses: a drop on the panel or at the notch goes to the box it lands on (OWN-APP-1).
    static let dropsLabel = "BOX on the wheel adds to"
    static let storageLabel = "Box storage"
    static let emptyLabel = "Empty Box Storage"
    static let emptyQuestion = "Empty box storage?"
    static let emptyAnswer = "Empty"

    /// "1.2 GB": decimal, as Finder and the box's overflow menu show it.
    static func storageValue(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    let model: SettingsModel

    static func label(_ choice: BoxAutoClearChoice) -> String {
        switch choice {
        case .off: "Never"
        case .afterLeaving: "After they leave the box"
        case .after24Hours: "After 24 hours"
        }
    }

    static func label(_ choice: BoxDropsChoice) -> String {
        switch choice {
        case .recentBox: "The last box"
        case .newBox: "A new box"
        }
    }

    var body: some View {
        Section(Self.title) {
            Toggle(Self.trayLabel, isOn: model.binding(\.box.trayWhileDragging))
            Toggle(Self.shakeLabel, isOn: model.binding(\.box.shakeToOpen))
            Picker(Self.clearLabel, selection: model.binding(\.box.autoClear)) {
                ForEach(BoxAutoClearChoice.allCases, id: \.self) { Text(Self.label($0)).tag($0) }
            }
            Picker(Self.dropsLabel, selection: model.binding(\.box.dropsGo)) {
                ForEach(BoxDropsChoice.allCases, id: \.self) { Text(Self.label($0)).tag($0) }
            }
            if let bytes = model.boxStorageBytes { BoxStorageRow(bytes: bytes, empty: model.emptyBoxStorage) }
        }
    }
}

/// Text recognition (D-M6-14): one picker; the Hindi choice is disabled, with a line saying why, where this Mac's
/// Vision has no Hindi (OWN-OCR-1).
struct TextRecognitionSection: View {
    static let title = "Text recognition"
    static let pickerLabel = "Read text in"
    static let noHindi = "Hindi isn't available on this version of macOS."

    struct Row: Equatable {
        let choice: TextLanguageChoice
        let enabled: Bool
    }

    let model: SettingsModel

    static func label(_ choice: TextLanguageChoice) -> String {
        switch choice {
        case .matchMine: "Match my languages"
        case .hindiAndEnglish: "Hindi and English"
        case .english: "English"
        }
    }

    static func rows(hindiAvailable: Bool) -> [Row] {
        TextLanguageChoice.allCases.map { Row(choice: $0, enabled: hindiAvailable || $0 != .hindiAndEnglish) }
    }

    static func help(hindiAvailable: Bool) -> String? { hindiAvailable ? nil : noHindi }

    var body: some View {
        Section(Self.title) {
            Picker(Self.pickerLabel, selection: model.binding(\.text.language)) {
                ForEach(Self.rows(hindiAvailable: model.hindiAvailable), id: \.choice) { row in
                    Text(Self.label(row.choice)).tag(row.choice).selectionDisabled(!row.enabled)
                }
            }
            if let help = Self.help(hindiAvailable: model.hindiAvailable) {
                Text(help).foregroundStyle(.secondary)
            }
        }
    }
}

/// "Box storage 1.2 GB" with Empty Box Storage; the button asks on the same row first, no alert (19c D-BL9).
struct BoxStorageRow: View {
    let bytes: Int64
    let empty: () -> Void
    @State private var asking = false

    var body: some View {
        LabeledContent(DropBoxSection.storageLabel) {
            HStack {
                Text(DropBoxSection.storageValue(bytes)).monospacedDigit()
                if asking {
                    Text(DropBoxSection.emptyQuestion)
                    Button(DropBoxSection.emptyAnswer) {
                        asking = false
                        empty()
                    }
                    Button("Cancel") { asking = false }
                } else {
                    Button(DropBoxSection.emptyLabel) { asking = true }.disabled(bytes == 0)
                }
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

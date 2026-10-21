import AppKit
import ZivletActions
import ZivletRuntime
import ZivletSettings
import ZivletUI
import os

/// Builds the Settings window on first use and keeps it in step with the store (D3): writes go through the store,
/// changes made elsewhere refresh the panes, and the helper versions are asked for once per opening.
final class SettingsWindowWiring {
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "settings")
    private let store: SettingsStore
    private let conversions: ConversionService
    private var controller: SettingsWindowController?
    private var model: SettingsModel?
    private var observer: Task<Void, Never>?

    init(store: SettingsStore, conversions: ConversionService) {
        self.store = store
        self.conversions = conversions
    }

    func show(_ pane: SettingsPane = .general) {
        if controller == nil { make() }
        guard let controller, let model else { return }
        Task { [conversions] in model.helperVersions = await conversions.helperVersions() }
        controller.show(pane)
        let window = controller.window?.windowNumber ?? 0
        logger.notice("Settings shown: \(pane.rawValue, privacy: .public) window \(window, privacy: .public)")
    }

    private func make() {
        let model = SettingsModel(
            settings: store.current, installedTerminals: TerminalCatalog.installed(SystemWorkspace()),
            commands: commands())
        let controller = SettingsWindowController(model: model)
        let changes = store.changes
        observer = Task { [weak model] in
            for await settings in changes { model?.refresh(settings) }
        }
        self.controller = controller
        self.model = model
    }

    private func commands() -> SettingsCommands {
        SettingsCommands(
            write: { [store] transform in
                store.update(transform)
                return store.current
            },
            chooseFallbackFolder: { [weak self] in self?.chooseFallbackFolder() },
            openAcknowledgements: Self.acknowledgements.map { url in { NSWorkspace.shared.open(url) } })
    }

    /// `Contents/Resources/Licenses/index.html`, when the build collected the licences (A13).
    private static var acknowledgements: URL? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Resources/Licenses/index.html")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func chooseFallbackFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose where Zivlet saves results when the original folder is read-only."
        panel.directoryURL = URL(filePath: store.current.output.fallbackFolder, directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.update { $0.with(\.output.fallbackFolder, url.path) }
        if store.current.output.fallbackFolder != url.path {
            logger.error("Fallback folder refused: \(url.path, privacy: .private)")
        }
    }
}

import AppKit
import ZivletActions
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime
import ZivletSettings
import ZivletUI
import os

/// Builds the Settings window on first use and keeps it in step with the store (D3): writes go through the store,
/// changes made elsewhere refresh the panes, and the helper versions are asked for once per opening. Copy
/// Diagnostics (P1-48) puts a redacted local report on the pasteboard, with every display's geometry (design/19
/// §3.3); nothing is sent anywhere.
final class SettingsWindowWiring {
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "settings")
    private let store: SettingsStore
    private let conversions: ConversionService
    private let displays: any DisplayGeometryProvider
    private let triggerTrace: () -> [String]
    private let checkForUpdates: (() -> Void)?
    private let boxStorage: (() -> Int64)?
    private let emptyBoxStorage: (() -> Void)?
    private var controller: SettingsWindowController?
    private var model: SettingsModel?
    private var observer: Task<Void, Never>?

    init(
        store: SettingsStore, conversions: ConversionService, displays: any DisplayGeometryProvider,
        checkForUpdates: (() -> Void)?, boxStorage: (() -> Int64)? = nil, emptyBoxStorage: (() -> Void)? = nil,
        triggerTrace: @escaping () -> [String]
    ) {
        self.store = store
        self.conversions = conversions
        self.displays = displays
        self.checkForUpdates = checkForUpdates
        self.boxStorage = boxStorage
        self.emptyBoxStorage = emptyBoxStorage
        self.triggerTrace = triggerTrace
    }

    func show(_ pane: SettingsPane = .general) {
        if controller == nil { make() }
        guard let controller, let model else { return }
        model.loginItem = LoginItemModel()  // the status can change in System Settings while the window is closed
        model.refreshBoxStorage()
        Task { [conversions] in model.helperVersions = await conversions.helperVersions() }
        controller.show(pane)
        let window = controller.window?.windowNumber ?? 0
        logger.notice("Settings shown: \(pane.rawValue, privacy: .public) window \(window, privacy: .public)")
    }

    private func make() {
        let model = SettingsModel(
            settings: store.current, installedTerminals: TerminalCatalog.installed(SystemWorkspace()),
            commands: commands())
        model.follow(displays)
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
            checkForUpdates: checkForUpdates,
            copyDiagnostics: { [weak self] in self?.copyDiagnostics() },
            openAcknowledgements: Self.acknowledgements.map { url in { NSWorkspace.shared.open(url) } },
            boxStorage: boxStorage, emptyBoxStorage: emptyBoxStorage)
    }

    private func copyDiagnostics() {
        let settingsJSON = store.current.diagnosticsJSON
        let trace = triggerTrace()
        let displayLines = displays.displays.map(\.diagnosticsLine)
        let notchSeen = displays.hasBuiltInNotch
        Task { [conversions, logger] in
            let helpers = await conversions.helperVersions()
            let worker = await conversions.workerStatus().line
            let sources = await DiagnosticsCollector().collect(
                settingsJSON: settingsJSON, triggerTrace: trace, helpers: helpers
            ).with(displays: displayLines, builtInNotchSeen: notchSeen).with(worker: worker)
            do {
                let report = try await Diagnostics.build(sources)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                logger.notice("Diagnostics copied: \(report.count, privacy: .public) characters")
            } catch {
                logger.error("Diagnostics not built: \(String(describing: error), privacy: .private)")
            }
        }
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

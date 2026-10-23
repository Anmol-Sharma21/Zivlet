import Observation
import SwiftUI
import ZivletActions
import ZivletCore
import ZivletEngineKit
import ZivletNotch
import ZivletSettings
import ZivletTrigger

/// `Settings` in this module means Zivlet's settings value, not SwiftUI's scene. Public signatures spell it out.
typealias Settings = ZivletSettings.Settings

/// What the panes can ask the app to do. `write` applies a transform through the settings store and returns what the
/// store kept (a refused value comes back unchanged); nil commands hide or disable their buttons.
public struct SettingsCommands {
    public var write: (_ transform: (ZivletSettings.Settings) -> ZivletSettings.Settings) -> ZivletSettings.Settings
    public var chooseFallbackFolder: () -> Void
    public var checkForUpdates: (() -> Void)?
    public var copyDiagnostics: (() -> Void)?
    public var openAcknowledgements: (() -> Void)?

    public init(
        write: @escaping (_ transform: (ZivletSettings.Settings) -> ZivletSettings.Settings) -> ZivletSettings.Settings,
        chooseFallbackFolder: @escaping () -> Void = {},
        checkForUpdates: (() -> Void)? = nil, copyDiagnostics: (() -> Void)? = nil,
        openAcknowledgements: (() -> Void)? = nil
    ) {
        self.write = write
        self.chooseFallbackFolder = chooseFallbackFolder
        self.checkForUpdates = checkForUpdates
        self.copyDiagnostics = copyDiagnostics
        self.openAcknowledgements = openAcknowledgements
    }
}

/// The Settings window's state (03b §8.1): the current settings, the terminals to offer and the helper versions.
@Observable
public final class SettingsModel {
    public private(set) var settings: ZivletSettings.Settings
    public let terminalChoices: [TerminalApp]
    public var helperVersions: [HelperVersion] = []
    /// Launch at login (D5); nil hides the row.
    public var loginItem: LoginItemModel?
    /// The latch of design/19 §3.2: this Mac has shown a built-in display with a notch (D-M5a-11).
    public var hasBuiltInNotch = false
    @ObservationIgnored let commands: SettingsCommands
    @ObservationIgnored private var notchWatch: Task<Void, Never>?

    public init(settings: ZivletSettings.Settings, installedTerminals: [TerminalApp], commands: SettingsCommands) {
        self.settings = settings
        let current = TerminalCatalog.resolve(settings.actions.terminal)
        terminalChoices = installedTerminals.contains(current) ? installedTerminals : installedTerminals + [current]
        self.commands = commands
    }

    /// Settings changed elsewhere (the status menu's Pause, onboarding).
    public func refresh(_ settings: ZivletSettings.Settings) { self.settings = settings }

    public func set<Value>(_ path: WritableKeyPath<ZivletSettings.Settings, Value>, _ value: Value) {
        settings = commands.write { $0.with(path, value) }
    }

    public func setModifier(_ modifier: ModifierMask, for mode: WheelMode) {
        set(\.trigger.bindings, BindingEditing.set(modifier, for: mode, in: settings.trigger.bindings))
    }

    /// The placement the picker shows: the stored choice, with Automatic resolved for this Mac.
    public var shownPlacement: HUDPlacement { settings.hud.placement.resolved(hasBuiltInNotch: hasBuiltInNotch) }

    var notchLabel: String { PlacementCopy.notchLabel(hasBuiltInNotch: hasBuiltInNotch) }

    /// A choice in the picker is stored as the explicit value, even when it equals what Automatic resolves to.
    public func choosePlacement(_ placement: HUDPlacement) { set(\.hud.placement, placement) }

    /// Reads the provider's notch latch now and after every display change.
    public func follow(_ provider: any DisplayGeometryProvider) {
        hasBuiltInNotch = provider.hasBuiltInNotch
        let changes = provider.changes
        notchWatch?.cancel()
        notchWatch = Task { [weak self, weak provider] in
            for await _ in changes {
                guard let self, let provider else { return }
                self.hasBuiltInNotch = provider.hasBuiltInNotch
            }
        }
    }

    func binding<Value>(_ path: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: path] }, set: { self.set(path, $0) })
    }

    func modifierBinding(for mode: WheelMode) -> Binding<UInt8> {
        Binding(
            get: { self.settings.trigger.bindings.modifier(for: mode).rawValue },
            set: { self.setModifier(ModifierMask(rawValue: $0), for: mode) })
    }
}

extension SettingsCommands {
    /// Keeps whatever is written, in memory only (previews and tests).
    static var preview: SettingsCommands {
        var stored = Settings.defaults
        return SettingsCommands(write: { transform in
            stored = transform(stored)
            return stored
        })
    }
}

extension TerminalApp {
    static let terminal = TerminalCatalog.standard
    static let ghostty = TerminalCatalog.resolve("com.mitchellh.ghostty")
    static let warp = TerminalCatalog.resolve("dev.warp.Warp-Stable")
}

extension SettingsModel {
    static var preview: SettingsModel { preview(installedTerminals: [.terminal]) }

    static func preview(installedTerminals: [TerminalApp]) -> SettingsModel {
        let model = SettingsModel(settings: .defaults, installedTerminals: installedTerminals, commands: .preview)
        model.helperVersions = [
            HelperVersion(name: "FFmpeg", version: "9.0.2"), HelperVersion(name: "libwebp", version: "1.6.0"),
            HelperVersion(name: "resvg", version: "0.47.0"),
        ]
        return model
    }
}

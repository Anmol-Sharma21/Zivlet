import AppKit
import ZivletRuntime
import ZivletSettings
import ZivletTriggerHost
import ZivletWheel

/// Applies `Settings` to the running parts (D2): trigger bindings and rules, Pause, Sound and Haptics, the wheel
/// theme, reveal in Finder, the fallback folder and the terminal. Applied once at launch and again on every change.
final class SettingsWiring {
    let store: SettingsStore
    let feedback = SystemWheelFeedback()
    private let conversions: ConversionService
    private weak var trigger: TriggerHost?
    /// Set before `attach`; follows Settings › Updates (D-M4-11).
    var updater: UpdaterWiring?
    private var applied: Settings?
    private var observer: Task<Void, Never>?
    /// `-ZivletRevealResults NO` on the command line (demo scripts) turns reveal off for that run only.
    private let revealOverride: Bool? = SettingsWiring.launchOverride(SettingsStore.legacyRevealKey)

    init(store: SettingsStore = SettingsStore(), conversions: ConversionService) {
        self.store = store
        self.conversions = conversions
    }

    var settings: Settings { store.current }
    var revealsResults: Bool { revealOverride ?? settings.output.revealResults }
    var terminalID: String { settings.actions.terminal }
    var wheelTheme: WheelTheme { WheelTheme(rawValue: settings.feedback.theme.rawValue) ?? .glass }

    /// Applies the current settings to `trigger` (starting it unless paused) and follows later changes.
    func attach(_ trigger: TriggerHost) {
        self.trigger = trigger
        apply(store.current)
        let changes = store.changes
        observer = Task { [weak self] in
            for await settings in changes { self?.apply(settings) }
        }
    }

    private func apply(_ settings: Settings) {
        let previous = applied
        applied = settings
        if previous?.trigger != settings.trigger { applyTrigger(settings.trigger, wasPaused: previous?.trigger.paused) }
        if previous?.updates != settings.updates { updater?.apply(settings.updates) }
        feedback.apply(FeedbackSettings(sound: settings.feedback.sound, haptics: settings.feedback.haptics))
        if previous?.output.fallbackFolder != settings.output.fallbackFolder {
            let folder = URL(filePath: settings.output.fallbackFolder, directoryHint: .isDirectory)
            Task { [conversions] in await conversions.use(fallbackFolder: folder) }
        }
    }

    /// New bindings apply from the next edge (T19); Pause removes every monitor, Resume reinstalls them.
    private func applyTrigger(_ group: TriggerGroup, wasPaused: Bool?) {
        guard let trigger else { return }
        trigger.update(config: group.config)
        guard wasPaused != group.paused else { return }
        if group.paused { trigger.stop() } else { trigger.start() }
    }

    private static func launchOverride(_ key: String) -> Bool? {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments[key] != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }
}

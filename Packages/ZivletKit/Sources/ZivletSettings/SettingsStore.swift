import Foundation
import os

/// Loads, validates, persists and publishes `Settings` (03b §8.1). One JSON blob per group in `UserDefaults` under
/// `settings.<group>.v1`. A stored group that is unreadable or invalid is replaced by its default, with one error
/// line naming the group (never its value). An update that makes a group invalid keeps that group as it was.
@MainActor
public final class SettingsStore {
    /// The M3 "Reveal results in Finder" key; a stored value is read once into `output.revealResults`, then
    /// removed. As a launch argument (`-ZivletRevealResults NO`, used by the demo scripts) it is an override for that
    /// run only and is never migrated.
    public static let legacyRevealKey = "ZivletRevealResults"

    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "settings")

    public private(set) var current: Settings
    private let defaults: UserDefaults
    private var subscribers: [UUID: AsyncStream<Settings>.Continuation] = [:]

    /// `launchArguments` is the argument domain (`-Key value` pairs); keys found there are not migrated.
    public init(
        defaults: UserDefaults = .standard,
        launchArguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    ) {
        self.defaults = defaults
        current = Self.load(from: defaults)
        if launchArguments[Self.legacyRevealKey] == nil { migrateLegacyReveal() }
    }

    /// A new stream of every later change; each subscriber gets its own.
    public var changes: AsyncStream<Settings> {
        let (stream, continuation) = AsyncStream.makeStream(of: Settings.self, bufferingPolicy: .bufferingNewest(8))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// Applies `transform` to the current settings, keeps the groups that pass validation, writes the groups that
    /// changed and publishes the result when anything changed.
    public func update(_ transform: (Settings) -> Settings) {
        let candidate = transform(current)
        var next = current
        next.trigger = accept(
            candidate.trigger, old: current.trigger, name: "trigger", valid: SettingsValidation.isValid)
        next.feedback = accept(
            candidate.feedback, old: current.feedback, name: "feedback", valid: SettingsValidation.isValid)
        next.output = accept(candidate.output, old: current.output, name: "output", valid: SettingsValidation.isValid)
        next.actions = accept(
            candidate.actions, old: current.actions, name: "actions", valid: SettingsValidation.isValid)
        next.updates = accept(
            candidate.updates, old: current.updates, name: "updates", valid: SettingsValidation.isValid)
        next.onboarding = accept(
            candidate.onboarding, old: current.onboarding, name: "onboarding", valid: SettingsValidation.isValid)
        guard next != current else { return }
        current = next
        for continuation in subscribers.values { continuation.yield(next) }
    }

    private func accept<Group: Codable & Equatable>(
        _ group: Group, old: Group, name: String, valid: (Group) -> Bool
    ) -> Group {
        guard group != old else { return old }
        guard valid(group) else {
            Self.logger.error("Settings change refused for group \(name, privacy: .public)")
            return old
        }
        Self.save(group, name: name, to: defaults)
        return group
    }

    private func migrateLegacyReveal() {
        guard let legacy = defaults.object(forKey: Self.legacyRevealKey) as? Bool else { return }
        defaults.removeObject(forKey: Self.legacyRevealKey)
        update { $0.with(\.output.revealResults, legacy) }
    }

    static func key(_ name: String) -> String { "settings.\(name).v1" }

    private static func load(from defaults: UserDefaults) -> Settings {
        var settings = Settings()
        settings.trigger = load("trigger", from: defaults, valid: SettingsValidation.isValid) ?? TriggerGroup()
        settings.feedback = load("feedback", from: defaults, valid: SettingsValidation.isValid) ?? FeedbackGroup()
        settings.output = loadOutput(from: defaults)
        settings.actions = load("actions", from: defaults, valid: SettingsValidation.isValid) ?? ActionsGroup()
        settings.updates = load("updates", from: defaults, valid: SettingsValidation.isValid) ?? UpdatesGroup()
        settings.onboarding =
            load("onboarding", from: defaults, valid: SettingsValidation.isValid) ?? OnboardingGroup()
        return settings
    }

    /// `~` in the stored folder is expanded here, once.
    private static func loadOutput(from defaults: UserDefaults) -> OutputGroup {
        let expand: (OutputGroup) -> OutputGroup = { group in
            var copy = group
            copy.fallbackFolder = SettingsValidation.expandingTilde(group.fallbackFolder)
            return copy
        }
        let valid: (OutputGroup) -> Bool = { SettingsValidation.isValid(expand($0)) }
        return load("output", from: defaults, valid: valid).map(expand) ?? OutputGroup()
    }

    /// Nil (with one error line) when the group is stored but unusable; nil silently when it was never stored.
    private static func load<Group: Decodable>(
        _ name: String, from defaults: UserDefaults, valid: (Group) -> Bool
    ) -> Group? {
        guard let stored = defaults.object(forKey: key(name)) else { return nil }
        guard let data = stored as? Data, let group = try? JSONDecoder().decode(Group.self, from: data), valid(group)
        else {
            logger.error("Settings group \(name, privacy: .public) was unreadable or invalid; using its defaults")
            return nil
        }
        return group
    }

    private static func save<Group: Encodable>(_ group: Group, name: String, to defaults: UserDefaults) {
        do {
            defaults.set(try JSONEncoder().encode(group), forKey: key(name))
        } catch {
            logger.error("Settings group \(name, privacy: .public) not saved")
        }
    }
}

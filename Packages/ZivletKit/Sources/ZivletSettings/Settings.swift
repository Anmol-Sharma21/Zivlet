import Foundation
import ZivletTrigger

/// The wheel's look as the user chose it; Reduce Transparency and Increase Contrast still force Solid at show time.
public enum ThemeChoice: String, Sendable, Codable, CaseIterable {
    case glass, solid
}

/// Trigger group (03a §1.5, 03b §8.1): which modifier opens which wheel, the re-tap rule, the held-at-start rule and
/// Pause.
public struct TriggerGroup: Sendable, Equatable {
    public var bindings = TriggerBindings.standard
    public var retapClosesWheel = true
    public var honorsModifierHeldAtDragStart = false
    public var paused = false

    public init() {}
}

/// Feedback group (03a §2.7): separate Sound and Haptics toggles, both on, and the theme.
public struct FeedbackGroup: Sendable, Equatable, Codable {
    public var sound = true
    public var haptics = true
    public var theme = ThemeChoice.glass

    public init() {}
}

/// Output group (03a §4.5, 01-prd FR-17): reveal in Finder, and where results go when the source folder is read-only.
/// `fallbackFolder` is an absolute path; it may not exist right now (checked where it is used).
public struct OutputGroup: Sendable, Equatable, Codable {
    public var revealResults = true
    public var fallbackFolder = URL.downloadsDirectory.path

    public init() {}
}

/// Actions group (03b §7): the terminal's bundle identifier.
public struct ActionsGroup: Sendable, Equatable, Codable {
    public static let standardTerminal = "com.apple.Terminal"

    public var terminal = ActionsGroup.standardTerminal

    public init() {}
}

/// Updates group (14 §6): Sparkle's two switches.
public struct UpdatesGroup: Sendable, Equatable, Codable {
    public var automaticChecks = true
    public var automaticDownloads = false

    public init() {}
}

/// Onboarding group (03b §8.2): resumable page, completion, and the coach's remaining real drags.
public struct OnboardingGroup: Sendable, Equatable, Codable {
    public static let practiceDrags = 3
    public static let pageCount = 7

    public var completed = false
    public var page = 0
    public var practiceDragsLeft = OnboardingGroup.practiceDrags

    public init() {}
}

/// Every setting (03b §8.1; the HUD group from design/19 §6; the box group from D-M5b-19). A value: change it with `with(_:_:)`, which returns a copy, and hand the copy to
/// `SettingsStore.update`.
public struct Settings: Sendable, Equatable {
    public var trigger = TriggerGroup()
    public var feedback = FeedbackGroup()
    public var output = OutputGroup()
    public var actions = ActionsGroup()
    public var updates = UpdatesGroup()
    public var onboarding = OnboardingGroup()
    public var hud = HUDGroup()
    public var box = BoxGroup()

    public init() {}

    public static let defaults = Settings()

    /// A copy with one value changed.
    public func with<Value>(_ path: WritableKeyPath<Settings, Value>, _ value: Value) -> Settings {
        var copy = self
        copy[keyPath: path] = value
        return copy
    }
}

extension Settings: Encodable {
    /// Every group as sorted, indented JSON with plain slashes, for Copy Diagnostics (P1-48), which removes the
    /// folder names before anything leaves the app.
    public var diagnosticsJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "(settings could not be encoded)" }
        return String(decoding: data, as: UTF8.self)
    }
}

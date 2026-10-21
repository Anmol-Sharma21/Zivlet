import Foundation
import Observation
import ZivletCore
import ZivletSettings
import ZivletTrigger

/// What onboarding can ask the app to do. `write` goes through the settings store and returns what it kept.
public struct OnboardingCommands {
    public var write: (_ transform: (ZivletSettings.Settings) -> ZivletSettings.Settings) -> ZivletSettings.Settings
    /// Finish was pressed: the app applies the login choice and closes the window.
    public var finished: (_ wantsLoginItem: Bool) -> Void
    /// Copies Zivlet to /Applications and relaunches; returns a sentence when that failed. Nil when not needed.
    public var moveToApplications: (() -> String?)?

    public init(
        write: @escaping (_ transform: (ZivletSettings.Settings) -> ZivletSettings.Settings) -> ZivletSettings.Settings,
        finished: @escaping (_ wantsLoginItem: Bool) -> Void = { _ in },
        moveToApplications: (() -> String?)? = nil
    ) {
        self.write = write
        self.finished = finished
        self.moveToApplications = moveToApplications
    }
}

/// The onboarding window's state (03b §8.2): the flow, the settings it reads and writes, and each page's choices.
@Observable
public final class OnboardingModel {
    public private(set) var flow: OnboardingFlow
    public private(set) var settings: ZivletSettings.Settings
    /// Page 6: "Open Zivlet at login", on by default and applied at Finish.
    public var wantsLoginItem = true
    /// Page 7: the sentence after a failed Move to Applications.
    public private(set) var moveError: String?
    @ObservationIgnored let commands: OnboardingCommands

    public init(settings: ZivletSettings.Settings, commands: OnboardingCommands) {
        self.settings = settings
        self.commands = commands
        flow = OnboardingFlow(storedPage: settings.onboarding.page)
    }

    public func next() { show(flow.next().page) }
    public func back() { show(flow.back().page) }

    /// Jumps to `page` and stores it, so quitting resumes there.
    public func show(_ page: OnboardingPage) {
        flow = OnboardingFlow(page: page, isCompleted: flow.isCompleted)
        settings = commands.write { $0.with(\.onboarding.page, page.rawValue) }
    }

    /// The only place that writes `completed` (03b §8.2).
    public func finish() {
        flow = flow.finish()
        settings = commands.write { $0.with(\.onboarding.completed, true).with(\.onboarding.page, 0) }
        commands.finished(wantsLoginItem)
    }

    public func set<Value>(_ path: WritableKeyPath<ZivletSettings.Settings, Value>, _ value: Value) {
        settings = commands.write { $0.with(path, value) }
    }

    public func moveToApplications() {
        moveError = commands.moveToApplications?()
    }

    /// The key that opens `mode`'s wheel, as a key cap ("⇧").
    public func keyCap(for mode: WheelMode) -> String { settings.trigger.bindings.modifier(for: mode).symbols }
}

extension OnboardingModel {
    static func preview(
        settings: ZivletSettings.Settings = .defaults, onWrite: @escaping (ZivletSettings.Settings) -> Void = { _ in }
    ) -> OnboardingModel {
        var stored = settings
        let commands = OnboardingCommands(write: { transform in
            stored = transform(stored)
            onWrite(stored)
            return stored
        })
        return OnboardingModel(settings: settings, commands: commands)
    }
}

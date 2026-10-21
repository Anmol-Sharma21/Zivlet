import Foundation
import Observation
import ZivletCore
import ZivletSettings
import ZivletTrigger
import ZivletWheelCore

/// What onboarding can ask the app to do. `write` goes through the settings store and returns what it kept.
public struct OnboardingCommands {
    public var write: (_ transform: (ZivletSettings.Settings) -> ZivletSettings.Settings) -> ZivletSettings.Settings
    /// Finish was pressed: the app applies the login choice and closes the window.
    public var finished: (_ wantsLoginItem: Bool) -> Void
    /// Copies Zivlet to /Applications and relaunches; returns a sentence when that failed. Nil when not needed.
    public var moveToApplications: (() -> String?)?
    /// Shows the practice file in Finder, for dragging from there.
    public var revealSample: (URL) -> Void

    public init(
        write: @escaping (_ transform: (ZivletSettings.Settings) -> ZivletSettings.Settings) -> ZivletSettings.Settings,
        finished: @escaping (_ wantsLoginItem: Bool) -> Void = { _ in },
        moveToApplications: (() -> String?)? = nil, revealSample: @escaping (URL) -> Void = { _ in }
    ) {
        self.write = write
        self.finished = finished
        self.moveToApplications = moveToApplications
        self.revealSample = revealSample
    }
}

/// The onboarding window's state (03b §8.2): the flow, the settings it reads and writes, and each page's choices.
@Observable
public final class OnboardingModel {
    public private(set) var flow: OnboardingFlow
    public private(set) var settings: ZivletSettings.Settings
    /// Page 6: "Open Zivlet at login", applied at Finish. On by default the first time; when onboarding is reopened
    /// after it was finished (practice from the menu), it starts from the login item's current state.
    public var wantsLoginItem: Bool
    /// Page 7: the sentence after a failed Move to Applications.
    public private(set) var moveError: String?
    /// The lessons of the practice page on screen; nil on other pages.
    private(set) var practice: PracticeCoordinator?
    /// The practice file, when it could be drawn.
    public var sampleURL: URL?
    @ObservationIgnored let commands: OnboardingCommands

    public init(settings: ZivletSettings.Settings, commands: OnboardingCommands, loginItemIsOn: Bool = false) {
        self.settings = settings
        self.commands = commands
        wantsLoginItem = settings.onboarding.completed ? loginItemIsOn : true
        flow = OnboardingFlow(storedPage: settings.onboarding.page)
        practice = PracticeCoordinator(page: flow.page)
    }

    public func next() { show(flow.next().page) }
    public func back() { show(flow.back().page) }

    /// Jumps to `page` and stores it, so quitting resumes there.
    public func show(_ page: OnboardingPage) {
        flow = OnboardingFlow(page: page, isCompleted: flow.isCompleted)
        practice = PracticeCoordinator(page: page)
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

    /// A wheel selection during practice is taken here and never run; true when it was taken.
    public func receive(_ selection: WheelSelection) -> Bool {
        guard let practice else { return false }
        self.practice = practice.receiving(selection)
        return true
    }

    /// The coaching line under the sample, on practice pages.
    public var practiceMessage: String? { practice?.message(keyCap: keyCap(for:)) }

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

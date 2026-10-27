import ZivletCore

/// Whether text recognition still needs its one-time warm-up (P2-103, D-M6-16): after onboarding, and again when
/// the OS build or the language set changes. An interrupted warm-up (a worker crash) stays needed but is not tried
/// again in the same launch, so a crashing model never loops; the next launch, or a language change, tries once more.
public struct WarmupState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case needed, running, done
    }

    public let phase: Phase
    /// The OS build and languages this state is about.
    public let record: TextWarmupRecord
    let attemptedThisLaunch: Bool

    public static func initial(stored: TextWarmupRecord?, current: TextWarmupRecord) -> WarmupState {
        WarmupState(phase: stored == current ? .done : .needed, record: current, attemptedThisLaunch: false)
    }

    public var shouldStart: Bool { phase == .needed && !attemptedThisLaunch }

    public func started() -> WarmupState {
        WarmupState(phase: .running, record: record, attemptedThisLaunch: true)
    }

    /// Done: `record` is what the app stores.
    public func finished() -> WarmupState {
        WarmupState(phase: .done, record: record, attemptedThisLaunch: true)
    }

    public func interrupted() -> WarmupState {
        WarmupState(phase: .needed, record: record, attemptedThisLaunch: true)
    }

    /// The language choice or the OS build changed: a new record needs its own warm-up, which may run once.
    public func changed(to current: TextWarmupRecord) -> WarmupState {
        guard current != record else { return self }
        return WarmupState(phase: .needed, record: current, attemptedThisLaunch: false)
    }
}

extension TextWarmupRecord {
    public init(osBuild: String, languages: [LanguageTag]) {
        self.init(osBuild: osBuild, languages: languages.map(\.identifier))
    }
}

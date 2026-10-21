import ZivletSettings

/// The seven onboarding pages (03b §8.2), in order. The raw value is what Settings stores.
public enum OnboardingPage: Int, CaseIterable, Sendable {
    case welcome, practiceConvert, practiceToolsActions, keyboard, privacy, loginAndUpdates, location
}

/// Where onboarding is (03b §8.2): pure and resumable. `next` and `back` stay within the pages; only `finish`
/// completes it.
public struct OnboardingFlow: Sendable, Equatable {
    public let page: OnboardingPage
    public let isCompleted: Bool

    public init(page: OnboardingPage, isCompleted: Bool = false) {
        self.page = page
        self.isCompleted = isCompleted
    }

    /// A stored page outside the range starts again at Welcome.
    public init(storedPage: Int) {
        self.init(page: OnboardingPage(rawValue: storedPage) ?? .welcome)
    }

    public var isFirst: Bool { page == OnboardingPage.allCases.first }
    public var isLast: Bool { page == OnboardingPage.allCases.last }

    public func next() -> OnboardingFlow { moved(by: 1) }
    public func back() -> OnboardingFlow { moved(by: -1) }
    public func finish() -> OnboardingFlow { OnboardingFlow(page: page, isCompleted: true) }

    private func moved(by step: Int) -> OnboardingFlow {
        OnboardingFlow(page: OnboardingPage(rawValue: page.rawValue + step) ?? page, isCompleted: isCompleted)
    }
}

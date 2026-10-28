import Foundation

/// Where Suggest gets a strong password (P2-101, plan 20c B5, D-M7-27): the system's generator in the app, a fake in
/// tests and demos. Nil means none could be made; the button then hides.
public protocol PasswordSuggesting: AnyObject {
    func suggest() -> String?
}

#if DEBUG
    /// Gives the same text every time (or nothing) and counts the calls; for tests and the DEBUG demos, which never
    /// call the system's generator.
    public final class FakeSuggester: PasswordSuggesting {
        private let text: String?
        public private(set) var calls = 0

        public init(_ text: String?) { self.text = text }

        public func suggest() -> String? {
            calls += 1
            return text
        }
    }
#endif

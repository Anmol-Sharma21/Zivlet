/// A toast's text in two styles (19b D-NL7, D-NL8): a primary line in parts (`LinePart`) and an optional secondary
/// one, side by side without a separator. Which of the two gives way first depends on the state: a saved toast keeps
/// its sizes, a failure keeps its reason.
public struct NotchToastLine: Sendable, Equatable {
    public let primary: [LinePart]
    public let secondary: String?
    /// The secondary line shortens before the primary one (the failure's file name).
    public let secondaryGivesWay: Bool

    public init(primary: [LinePart], secondary: String? = nil, secondaryGivesWay: Bool = false) {
        self.primary = primary
        self.secondary = secondary
        self.secondaryGivesWay = secondaryGivesWay
    }

    /// Both lines as plain text, for a label when the board has no spoken form.
    public var joined: String { ([LinePart.joined(primary)] + [secondary].compactMap { $0 }).joined(separator: " ") }
}

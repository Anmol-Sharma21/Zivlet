/// What an action did, for the HUD: a short toast on success, the failure in Zivlet's words otherwise.
public enum ActionOutcome: Sendable, Equatable {
    case done(toast: String)
    case failed(ActionError)
    /// The person cancelled (the AirDrop sheet, the Move panel): nothing to show.
    case cancelled

    /// The toast line, or nil when the outcome is not a success.
    public var toast: String? {
        switch self {
        case .done(let toast): toast
        case .failed, .cancelled: nil
        }
    }
}

/// "1 item", "3 items": the count and the noun, singular for one.
nonisolated public func counted(_ count: Int, _ singular: String) -> String {
    count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
}

import ZivletCore

/// The non-modal result card (03b §7 "Failure UI"): one sentence, then one line per item, and optional details.
public struct ActionCard: Sendable, Equatable {
    public let title: String
    public let lines: [String]
    public let detail: String?

    public init(title: String, lines: [String] = [], detail: String? = nil) {
        self.title = title
        self.lines = lines
        self.detail = detail
    }

    init(_ error: ActionError) { self.init(title: error.userMessage, detail: error.detail) }

    func adding(_ more: [String]) -> ActionCard { ActionCard(title: title, lines: lines + more, detail: detail) }
}

/// What the HUD shows after an action (03b §7 "Success feedback"): a toast, with Undo when `undo` is set; a toast
/// plus a card when part of the drop was left out or failed; a card alone; or nothing after a cancel.
public enum ActionResult: Sendable, Equatable {
    case done(toast: String, undo: BatchID?)
    case partial(toast: String, card: ActionCard, undo: BatchID?)
    case failed(ActionCard)
    case cancelled

    init(_ outcome: ActionOutcome) {
        switch outcome {
        case .done(let toast): self = .done(toast: toast, undo: nil)
        case .failed(let error): self = .failed(ActionCard(error))
        case .cancelled: self = .cancelled
        }
    }

    public var toast: String? {
        switch self {
        case .done(let toast, _), .partial(let toast, _, _): toast
        case .failed, .cancelled: nil
        }
    }

    public var card: ActionCard? {
        switch self {
        case .partial(_, let card, _), .failed(let card): card
        case .done, .cancelled: nil
        }
    }

    public var undo: BatchID? {
        switch self {
        case .done(_, let undo), .partial(_, _, let undo): undo
        case .failed, .cancelled: nil
        }
    }

    /// Items refused at the boundary are always listed (a cancel stays silent: the person stopped the action).
    func listing(_ rejected: [RejectedItem]) -> ActionResult {
        guard !rejected.isEmpty else { return self }
        let lines = rejected.map(\.cardLine)
        switch self {
        case .done(let toast, let undo):
            let title = counted(rejected.count, "item") + (rejected.count == 1 ? " was" : " were") + " left out."
            return .partial(toast: toast, card: ActionCard(title: title, lines: lines), undo: undo)
        case .partial(let toast, let card, let undo):
            return .partial(toast: toast, card: card.adding(lines), undo: undo)
        case .failed(let card): return .failed(card.adding(lines))
        case .cancelled: return .cancelled
        }
    }
}

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
/// plus a card when part of the drop was left out or failed; a card alone; or nothing after a cancel. A toast may
/// say how long it stays (`linger`), so the undo window it offers is the one the person gets: the Drop Box's Clear
/// offers Undo for 10 s (D-M5b-21); nil keeps the presenters' own times.
public enum ActionResult: Sendable, Equatable {
    case done(toast: String, undo: BatchID?, linger: Duration? = nil)
    case partial(toast: String, card: ActionCard, undo: BatchID?)
    case failed(ActionCard)
    case cancelled
    /// Copy Text's result (P2-104): "Text copied" with the text card below; no undo.
    case text(TextOutcome)

    public init(_ outcome: ActionOutcome) {
        switch outcome {
        case .done(let toast): self = .done(toast: toast, undo: nil)
        case .failed(let error): self = .failed(ActionCard(error))
        case .cancelled: self = .cancelled
        }
    }

    public var toast: String? {
        switch self {
        case .done(let toast, _, _), .partial(let toast, _, _): toast
        case .text: "Text copied"
        case .failed, .cancelled: nil
        }
    }

    public var card: ActionCard? {
        switch self {
        case .partial(_, let card, _), .failed(let card): card
        case .done, .cancelled, .text: nil
        }
    }

    public var undo: BatchID? {
        switch self {
        case .done(_, let undo, _), .partial(_, _, let undo): undo
        case .failed, .cancelled, .text: nil
        }
    }

    /// How long the toast stays, when the result says; nil leaves it to the presenter.
    public var linger: Duration? {
        switch self {
        case .done(_, _, let linger): linger
        case .text: TextOutcome.linger
        default: nil
        }
    }

    /// The text card's content, for Copy Text's result.
    public var text: TextOutcome? {
        if case .text(let outcome) = self { return outcome }
        return nil
    }

    /// Items refused at the boundary are always listed (a cancel stays silent: the person stopped the action).
    func listing(_ rejected: [RejectedItem]) -> ActionResult { listing(lines: rejected.map(\.cardLine)) }

    /// The same result with one card line per item that was left out (a Drop Box item that is missing, say); a
    /// success becomes a toast plus a card titled with the count.
    public func listing(lines: [String]) -> ActionResult {
        guard !lines.isEmpty else { return self }
        switch self {
        case .done(let toast, let undo, _):
            let title = counted(lines.count, "item") + (lines.count == 1 ? " was" : " were") + " left out."
            return .partial(toast: toast, card: ActionCard(title: title, lines: lines), undo: undo)
        case .partial(let toast, let card, let undo):
            return .partial(toast: toast, card: card.adding(lines), undo: undo)
        case .failed(let card): return .failed(card.adding(lines))
        case .cancelled: return .cancelled
        case .text: return self  // Copy Text checks its files before it runs; the wiring reports refusals itself
        }
    }
}

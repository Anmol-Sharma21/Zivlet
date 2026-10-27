import Foundation
import ZivletActions
import ZivletCore
import ZivletRuntime

/// One item of the Notch HUD: a conversion batch or an action result.
public enum NotchHUDItemID: Sendable, Hashable {
    case batch(BatchID)
    case action(Int)
}

/// What the collapsed tab shows (design/19 §4.3, 19b D-NL10): the target's family symbol left, count in the middle,
/// ring, stepped glyph or error glyph right.
public struct TabContent: Sendable, Equatable {
    public enum Icon: Sendable, Equatable {
        /// The format family of the batch's target: what is being made.
        case family(FormatFamily)
        /// A long action still running: its own symbol (Copy Text's text viewfinder).
        case symbol(String)
        case action
    }

    public enum Ring: Sendable, Equatable {
        case fraction(Double)
        /// The stepped glyph of a job of unknown length (D-N7): one of 8 positions.
        case step(Int)
        /// Nothing is working: a check mark.
        case done
    }

    public let icon: Icon
    public let ring: Ring
    /// "3 jobs" when the display has more than one item.
    public let count: String?
    /// An item failed: the error glyph replaces the ring.
    public let failed: Bool

    public init(icon: Icon, ring: Ring, count: String?, failed: Bool) {
        self.icon = icon
        self.ring = ring
        self.count = count
        self.failed = failed
    }

    /// The same tab apart from the ring's drawn step or the stepped glyph, which redraw at most four times a second.
    func sameShape(as other: TabContent) -> Bool {
        icon == other.icon && count == other.count && failed == other.failed && ring.kind == other.ring.kind
    }
}

extension TabContent.Ring {
    fileprivate var kind: Int {
        switch self {
        case .fraction: 0
        case .step: 1
        case .done: 2
        }
    }

    /// What is drawn: the ring's visible step (19b §6.2, D-NL12), so a new percent the ring cannot show is the same
    /// picture and neither redraws the tab nor refreshes the spoken value.
    var shown: Int {
        switch self {
        case .fraction(let value): VisibleProgress(value, steps: NotchHUDBoard.ringSteps).step
        case .step(let step): step
        case .done: 0
        }
    }
}

/// One row of the expanded list (several items): failed rows first.
public struct NotchHUDRow: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        case working(Double?)
        case saved
        case failed
        case action
        /// Every job of the batch was cancelled: nothing saved, nothing failed.
        case cancelled
    }

    public let id: NotchHUDItemID
    /// The spoken title and detail (unchanged from M5a).
    public let title: String
    public let detail: String
    public let status: Status
    /// What the row draws on its one line, and its short status beside it (19b §5): "40%", the sizes, "Failed".
    public let line: String
    public let summary: String

    init(id: NotchHUDItemID, title: String, detail: String, status: Status, line: String? = nil, summary: String = "") {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.line = line ?? title
        self.summary = summary
    }
}

/// A VoiceOver announcement from the board (design/19 §5.5); progress percentages are never announced.
public struct Announcement: Sendable, Equatable {
    public let text: String
    public let highPriority: Bool

    public init(text: String, highPriority: Bool) {
        self.text = text
        self.highPriority = highPriority
    }
}

/// The glyph in front of a toast line: a check mark, the error glyph (a shape, not colour alone), an action icon, the
/// neutral stop glyph of a batch whose jobs were all cancelled, or the tab's ring while a long action works.
public enum ToastGlyph: Sendable, Equatable {
    case saved, failed, action, cancelled, working
}

/// One item and its timer. `linger` runs while the item rests as a toast; a failure's runs only for its first 4 s,
/// after which it waits in the tab until closed.
struct NotchHUDItem: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case batch(BatchSnapshot)
        case action(ActionResult)
    }

    let id: NotchHUDItemID
    var kind: Kind
    var linger: LingerTimer?
    /// A failure's toast is over; it rests in the tab.
    var waits = false
    /// When the current item's length became unknown, for the stepped glyph.
    var indeterminateSince: Duration?
    /// An undo is in flight: the linger waits for its reply, whatever the hold does.
    var paused = false
    /// What the batch's last applied snapshot draws and speaks (19b §6.2).
    var visible: VisibleKey?

    var snapshot: BatchSnapshot? {
        if case .batch(let snapshot) = kind { return snapshot }
        return nil
    }

    var isWorking: Bool {
        switch kind {
        case .batch(let snapshot): !snapshot.isFinished
        case .action(let result): result.working != nil
        }
    }

    /// How far a working item is, when it knows.
    var fraction: Double? {
        switch kind {
        case .batch(let snapshot): snapshot.fraction
        case .action(let result): result.working?.fraction
        }
    }

    /// A finished batch with nothing saved and nothing failed (BatchPresentation's `.cancelled`).
    var isCancelled: Bool {
        guard let snapshot, snapshot.isFinished else { return false }
        return snapshot.outputs.isEmpty && snapshot.failures.isEmpty
    }

    var isFailure: Bool {
        switch kind {
        case .batch(let snapshot): snapshot.isFinished && !snapshot.failures.isEmpty
        case .action(let result): result.card != nil
        }
    }
}

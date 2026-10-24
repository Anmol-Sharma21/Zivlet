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

    /// The same tab apart from the ring's percent or step, which redraws at most four times a second.
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

    /// What is drawn: whole percents, so 40.1 % and 40.2 % are the same picture.
    var shown: Int {
        switch self {
        case .fraction(let value): Int((value * 100).rounded(.down))
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
    }

    public let id: NotchHUDItemID
    public let title: String
    public let detail: String
    public let status: Status
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

/// The glyph in front of a toast line: a check mark, the error glyph (a shape, not colour alone) or an action icon.
public enum ToastGlyph: Sendable, Equatable {
    case saved, failed, action
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

    var isWorking: Bool { snapshot.map { !$0.isFinished } ?? false }

    var isFailure: Bool {
        switch kind {
        case .batch(let snapshot): snapshot.isFinished && !snapshot.failures.isEmpty
        case .action(let result): result.card != nil
        }
    }
}

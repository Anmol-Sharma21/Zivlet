import Foundation

/// The outcome of one undo, and the sentence the result card shows for it.
public struct UndoResult: Sendable, Equatable {
    public let kind: UndoEntry.Kind
    /// Conversion outputs or copies moved to the Trash.
    public let trashed: [URL]
    /// Moved items put back, at their old paths.
    public let restored: [URL]
    public let skipped: [UndoSkip]

    public init(trashed: [URL], skipped: [UndoSkip]) {
        self.init(kind: .conversion, trashed: trashed, restored: [], skipped: skipped)
    }

    public init(kind: UndoEntry.Kind, trashed: [URL] = [], restored: [URL] = [], skipped: [UndoSkip]) {
        self.kind = kind
        self.trashed = trashed
        self.restored = restored
        self.skipped = skipped
    }

    /// Some files were refused by the Trash, or could not be moved back, and stay in the history.
    public var canRetry: Bool { skipped.contains { $0.reason == .trashFailed || $0.reason == .moveFailed } }

    /// One sentence per outcome, the done part first; "Moved to the Trash." or "Moved back." alone when nothing was
    /// left in place.
    public var message: String {
        let isMove = kind == .move
        guard !skipped.isEmpty else { return isMove ? "Moved back." : "Moved to the Trash." }
        let done = isMove ? restored.count : trashed.count
        let lead = done == 0 ? [] : [Self.count(done, kind) + (isMove ? " moved back." : " moved to the Trash.")]
        let reasons: [UndoSkipReason] = [.changed, .missing, .trashFailed, .originalTaken, .moveFailed]
        let left = reasons.flatMap { reason -> [String] in
            let urls = skipped.filter { $0.reason == reason }.map(\.url)
            if kind == .copy, reason == .changed { return urls.map(Self.keptCopy) }
            return urls.isEmpty ? [] : [Self.sentence(reason, count: urls.count, kind: kind)]
        }
        return (lead + left).joined(separator: " ")
    }

    /// A copy that changed is named: the person may have started working in it.
    private static func keptCopy(_ url: URL) -> String {
        "\(url.lastPathComponent) changed since it was copied, so it was kept."
    }

    /// "1 file", "3 files" for conversions; "1 item", "3 items" for moves and copies (they may be folders).
    private static func count(_ count: Int, _ kind: UndoEntry.Kind) -> String {
        let noun = kind == .conversion ? "file" : "item"
        return count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    private static func sentence(_ reason: UndoSkipReason, count: Int, kind: UndoEntry.Kind) -> String {
        let one = count == 1
        let subject = Self.count(count, kind)
        let pronoun = one ? "it was" : "they were"
        switch reason {
        case .changed:
            let event = kind == .move ? "moved" : "saved"
            return "\(subject) changed since \(pronoun) \(event), so \(pronoun) left in place."
        case .missing: return subject + (one ? " was" : " were") + " no longer there."
        case .trashFailed: return subject + " couldn't be moved to the Trash; Undo can try again."
        case .originalTaken:
            return subject + " stayed put because something else is in "
                + (one ? "its old place." : "their old places.")
        case .moveFailed: return subject + " couldn't be moved back; Undo can try again."
        }
    }
}

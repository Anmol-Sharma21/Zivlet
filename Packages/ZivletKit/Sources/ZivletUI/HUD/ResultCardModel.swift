import Foundation
import ZivletCore
import ZivletRuntime

/// What a finished batch's card shows and offers (P1-41, 03a §4.5). Pure: derived from the snapshot alone.
public struct ResultCardModel: Sendable, Equatable {
    public enum Button: Sendable, Hashable {
        case undo, reveal, open, copy, showDetails, retry, close
    }

    public static let successLinger = Duration.seconds(4)

    public let title: String
    public let subtitle: String
    /// "photo.png · 2.1 MB → 640 KB", or "3 files · 5 MB → 1 MB"; nil when nothing was saved.
    public let sizeLine: String?
    public let notes: [String]
    public let details: String?
    public let buttons: [Button]
    /// How long the card stays on its own; nil = until closed (anything that failed).
    public let lingers: Duration?
    public let holdsWhileHovered: Bool
    public let outputs: [URL]

    public init(_ snapshot: BatchSnapshot, registry: FormatRegistry = .standard) {
        let shown = BatchPresentation.make(snapshot, registry: registry)
        title = shown.title
        subtitle = shown.subtitle
        sizeLine = Self.sizeLine(snapshot)
        notes = shown.notes
        details = shown.detail
        outputs = snapshot.outputs.map(\.url)
        buttons = Self.buttons(shown)
        lingers = snapshot.failures.isEmpty ? Self.successLinger : nil
        holdsWhileHovered = true
    }

    static func buttons(_ shown: BatchPresentation) -> [Button] {
        shown.canUndo ? [.undo, .reveal, .open, .copy] : [.close]
    }

    /// Before → after for the saved items only, in Finder's file-size style.
    static func sizeLine(_ snapshot: BatchSnapshot) -> String? {
        let saved = snapshot.items.compactMap { item in item.state.published.map { (item, $0) } }
        guard let first = saved.first else { return nil }
        let before = saved.reduce(Int64(0)) { $0 + ($1.0.source?.byteCount ?? 0) }
        let after = saved.reduce(Int64(0)) { $0 + $1.1.byteCount }
        let label = saved.count == 1 ? first.1.url.lastPathComponent : "\(saved.count) files"
        return "\(label) · \(size(before)) → \(size(after))"
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

/// The success card's linger (P1-41): runs from `started`, pauses while hovered, and restarts in full when the
/// pointer leaves. Times are monotonic durations.
public struct LingerTimer: Sendable, Equatable {
    public let duration: Duration
    /// When it runs out; nil while hovered or not started.
    public let deadline: Duration?

    public init(duration: Duration) { self.init(duration: duration, deadline: nil) }

    private init(duration: Duration, deadline: Duration?) {
        self.duration = duration
        self.deadline = deadline
    }

    public func started(at now: Duration) -> LingerTimer { LingerTimer(duration: duration, deadline: now + duration) }
    public func hovered(at now: Duration) -> LingerTimer { LingerTimer(duration: duration, deadline: nil) }
    public func unhovered(at now: Duration) -> LingerTimer { started(at: now) }
    public func expired(at now: Duration) -> Bool { deadline.map { now >= $0 } ?? false }
}

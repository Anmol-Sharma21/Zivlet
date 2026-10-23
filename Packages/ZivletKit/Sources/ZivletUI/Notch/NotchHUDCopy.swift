import Foundation
import ZivletActions
import ZivletCore
import ZivletRuntime

/// The Notch HUD's own words (design/19 §4.3, *new*); everything else comes from `HUDCopy`, `ResultCardModel`,
/// `BatchPresentation` and `ActionResult`.
enum NotchHUDCopy {
    static let islandLabel = "Zivlet progress and results"
    static let showAction = "Show Progress and Results"

    static func jobs(_ count: Int) -> String { "\(count) jobs" }
    static func more(_ count: Int) -> String { "+\(count) more" }
    static func failedCount(_ count: Int) -> String { "\(count) failed" }

    /// "Saved photo.jpg · 2.1 MB → 640 KB": the owner's example in front of the card's size line.
    static func saved(_ snapshot: BatchSnapshot) -> String {
        ResultCardModel.sizeLine(snapshot).map { "Saved \($0)" } ?? BatchPresentation.make(snapshot).title
    }

    /// The card's title and subtitle on one line.
    static func failure(_ snapshot: BatchSnapshot) -> String {
        let shown = BatchPresentation.make(snapshot)
        return shown.subtitle.isEmpty ? shown.title : "\(shown.title) · \(shown.subtitle)"
    }

    /// A finished batch, announced once: "Saved photo.jpg" (medium), or the failure card's title (high).
    static func announcement(finished snapshot: BatchSnapshot) -> Announcement {
        let shown = BatchPresentation.make(snapshot)
        guard snapshot.failures.isEmpty else { return Announcement(text: shown.title, highPriority: true) }
        let outputs = snapshot.outputs
        switch outputs.count {
        case 0: return Announcement(text: shown.title, highPriority: false)
        case 1: return Announcement(text: "Saved \(outputs[0].url.lastPathComponent)", highPriority: false)
        default: return Announcement(text: "Saved \(outputs.count) files", highPriority: false)
        }
    }

    static func action(_ result: ActionResult) -> String { result.toast ?? result.card?.title ?? "" }

    /// "Converting to PNG, file0.heic": announced once when a batch appears.
    static func started(_ snapshot: BatchSnapshot) -> String {
        let title = HUDCopy.title(target: snapshot.target)
        guard let name = snapshot.current?.item.name ?? snapshot.items.first?.name else { return title }
        return "\(title), \(name)"
    }

    /// The form a screen reader speaks: separators as words, so it does not read "right arrow".
    static func spoken(_ line: String) -> String {
        line.replacingOccurrences(of: " · ", with: ", ").replacingOccurrences(of: " → ", with: " to ")
    }
}

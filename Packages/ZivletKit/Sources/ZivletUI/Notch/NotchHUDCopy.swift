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
    static func saved(_ snapshot: BatchSnapshot) -> String { LinePart.joined(savedParts(snapshot)) }

    /// "Saved photo.jpg" gives way; " · 2.1 MB → 640 KB" stays whole.
    static func savedParts(_ snapshot: BatchSnapshot) -> [LinePart] {
        guard let line = ResultCardModel.sizeLine(snapshot), let split = line.range(of: " · ", options: .backwards)
        else { return [LinePart(text: BatchPresentation.make(snapshot).title, givesWay: false)] }
        return [
            LinePart(text: "Saved \(line[..<split.lowerBound])", givesWay: true),
            LinePart(text: String(line[split.lowerBound...]), givesWay: false),
        ]
    }

    /// "Saved photo.jpg" (gives way) and "2.1 MB → 640 KB" (stays) in two styles.
    static func savedLine(_ snapshot: BatchSnapshot) -> NotchToastLine {
        split(savedParts(snapshot), secondaryGivesWay: false)
    }

    /// The reason without its full stop (stays) and the file name (gives way) in two styles.
    static func failureLine(_ snapshot: BatchSnapshot) -> NotchToastLine {
        split(failureParts(snapshot), secondaryGivesWay: true)
    }

    /// The first part as the primary line, the rest without its separator as the secondary one.
    private static func split(_ parts: [LinePart], secondaryGivesWay: Bool) -> NotchToastLine {
        guard let first = parts.first, parts.count > 1 else { return NotchToastLine(primary: parts) }
        let rest = LinePart.joined(Array(parts.dropFirst()))
        let secondary = rest.hasPrefix(" · ") ? String(rest.dropFirst(3)) : rest
        return NotchToastLine(primary: [first], secondary: secondary, secondaryGivesWay: secondaryGivesWay)
    }

    /// The card's title and subtitle on one line.
    static func failure(_ snapshot: BatchSnapshot) -> String { LinePart.joined(failureParts(snapshot)) }

    /// The reason stays (without its full stop before the separator); the name after it gives way.
    static func failureParts(_ snapshot: BatchSnapshot) -> [LinePart] {
        let shown = BatchPresentation.make(snapshot)
        guard !shown.subtitle.isEmpty else { return [LinePart(text: shown.title, givesWay: false)] }
        let reason = shown.title.hasSuffix(".") ? String(shown.title.dropLast()) : shown.title
        return [LinePart(text: reason, givesWay: false), LinePart(text: " · \(shown.subtitle)", givesWay: true)]
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

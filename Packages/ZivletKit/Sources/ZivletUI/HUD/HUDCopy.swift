import Foundation
import ZivletCore
import ZivletRuntime

/// The working HUD's words (P1-40), Zivlet's own: "Converting to PNG" and "clip.mov · 2 of 5 · 42% · about 1 min
/// left", or "a.wav · 12.4 MB written" while the length is unknown.
public enum HUDCopy {
    public static func title(target: FormatID, registry: FormatRegistry = .standard) -> String {
        "Converting to \(registry.format(target).wheelLabel)"
    }

    /// "i of n" only for batches of more than one file.
    public static func working(
        name: String, index: Int, count: Int, fraction: Double?, eta: Duration?, bytes: Int64?
    ) -> String {
        LinePart.joined(
            workingParts(name: name, index: index, count: count, fraction: fraction, eta: eta, bytes: bytes))
    }

    /// The name gives way; " · 2 of 5 · 42% · about 1 min left" stays whole.
    static func workingParts(
        name: String, index: Int, count: Int, fraction: Double?, eta: Duration?, bytes: Int64?
    ) -> [LinePart] {
        var rest: [String] = []
        if count > 1 { rest.append("\(index) of \(count)") }
        if let fraction {
            rest.append("\(Int((fraction * 100).rounded(.down)))%")
        } else if let bytes {
            rest.append("\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) written")
        }
        if let eta { rest.append(timeLeft(eta)) }
        let name = LinePart(text: name, givesWay: true)
        guard !rest.isEmpty else { return [name] }
        return [name, LinePart(text: " · " + rest.joined(separator: " · "), givesWay: false)]
    }

    /// The line for a running batch in its parts; empty when nothing runs yet.
    static func workingParts(_ snapshot: BatchSnapshot) -> [LinePart] {
        guard let current = snapshot.current else { return [] }
        let progress = snapshot.currentProgress
        return workingParts(
            name: current.item.name, index: current.index + 1, count: snapshot.items.count,
            fraction: snapshot.isIndeterminate ? nil : snapshot.fraction, eta: progress?.eta,
            bytes: progress?.bytesWritten)
    }

    /// The line for a running batch: its current item, the batch percent (or the item's bytes), the item's ETA.
    public static func working(_ snapshot: BatchSnapshot) -> String { LinePart.joined(workingParts(snapshot)) }

    static let almostDone = Duration.seconds(10)

    /// Rough on purpose: an estimate that ticks every second looks more precise than it is.
    public static func timeLeft(_ eta: Duration) -> String {
        switch TimeLeft(eta) {
        case .almostDone: "almost done"
        case .underAMinute: "less than a minute left"
        case .minutes(let minutes): "about \(minutes) min left"
        case .hours(let hours): "about \(hours) hr left"
        }
    }

    /// The island's working card (19b §5, *new*): "almost done", "< 1 min", "3 min", "2 hr", from the same
    /// thresholds; the long form stays the spoken one.
    public static func shortTimeLeft(_ eta: Duration) -> String {
        switch TimeLeft(eta) {
        case .almostDone: "almost done"
        case .underAMinute: "< 1 min"
        case .minutes(let minutes): "\(minutes) min"
        case .hours(let hours): "\(hours) hr"
        }
    }

    /// The rough buckets both forms share.
    private enum TimeLeft {
        case almostDone, underAMinute, minutes(Int), hours(Int)

        init(_ eta: Duration) {
            let seconds = Double(eta.components.seconds)
            let minutes = Int((seconds / 60).rounded())
            if eta < HUDCopy.almostDone {
                self = .almostDone
            } else if seconds < 60 {
                self = .underAMinute
            } else if minutes < 90 {
                self = .minutes(minutes)
            } else {
                self = .hours(Int((seconds / 3_600).rounded()))
            }
        }
    }
}

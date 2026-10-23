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
        let seconds = Double(eta.components.seconds)
        if eta < almostDone { return "almost done" }
        if seconds < 60 { return "less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 90 { return "about \(minutes) min left" }
        return "about \(Int((seconds / 3_600).rounded())) hr left"
    }
}

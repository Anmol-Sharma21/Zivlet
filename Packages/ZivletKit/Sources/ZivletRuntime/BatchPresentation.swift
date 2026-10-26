import Foundation
import ZivletCore
import ZivletEngineKit

/// What the result HUD says for a batch (01-prd FR-14, 03a §4.5): Zivlet's own wording, derived purely from a
/// snapshot so the view stays a thin renderer.
public struct BatchPresentation: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case working, succeeded, partial, failed, cancelled }

    public let phase: Phase
    public let title: String
    public let subtitle: String
    /// 0…1 while working; nil once finished.
    public let fraction: Double?
    public let notes: [String]
    public let detail: String?

    public var canUndo: Bool { phase == .succeeded || phase == .partial }
    public var canReveal: Bool { canUndo }
    public var canCancel: Bool { phase == .working }

    public static func make(_ snapshot: BatchSnapshot, registry: FormatRegistry = .standard) -> BatchPresentation {
        let label = registry.format(snapshot.target).wheelLabel
        guard snapshot.isFinished else { return working(snapshot, label: label) }
        let notes = snapshot.items.flatMap(\.notes).uniqued().map(noteText) + fallbackNotes(snapshot)
        let saved = snapshot.outputs
        let failures = snapshot.failures
        let firstFailure = failures.first.map {
            (name: $0.name, copy: JobErrorCopy.copy(for: $0.error, registry: registry))
        }
        if failures.isEmpty, saved.isEmpty {
            return BatchPresentation(
                phase: .cancelled, title: "Cancelled", subtitle: "Nothing was saved.", fraction: nil, notes: [],
                detail: nil)
        }
        if failures.isEmpty {
            let title = saved.count == 1 ? "Saved \(saved[0].url.lastPathComponent)" : "Saved \(saved.count) files"
            let size = ByteCountFormatter.string(fromByteCount: saved.map(\.byteCount).reduce(0, +), countStyle: .file)
            return BatchPresentation(
                phase: .succeeded, title: title, subtitle: "\(label) · \(size)", fraction: nil, notes: notes,
                detail: nil)
        }
        let failure = firstFailure.map { "\($0.name): \($0.copy.message)" } ?? ""
        if saved.isEmpty {
            let title =
                snapshot.items.count == 1
                ? (firstFailure?.copy.message ?? "") : "None of the \(snapshot.items.count) files could be converted"
            return BatchPresentation(
                phase: .failed, title: title,
                subtitle: snapshot.items.count == 1 ? (firstFailure?.name ?? "") : failure,
                fraction: nil, notes: notes, detail: firstFailure?.copy.detail)
        }
        return BatchPresentation(
            phase: .partial, title: "Saved \(saved.count) of \(snapshot.items.count) files", subtitle: failure,
            fraction: nil, notes: notes, detail: firstFailure?.copy.detail)
    }

    static let retryingLine = "The converter stopped unexpectedly. Trying again…"

    private static func working(_ snapshot: BatchSnapshot, label: String) -> BatchPresentation {
        let percent = Int((snapshot.fraction * 100).rounded(.down))
        let position = snapshot.current.map { "\($0.item.name) · \($0.index + 1) of \(snapshot.items.count)" } ?? ""
        let retrying = snapshot.items.contains { $0.state == .retrying }
        return BatchPresentation(
            phase: .working, title: "Converting to \(label)",
            subtitle: retrying ? retryingLine : "\(position) · \(percent)%", fraction: snapshot.fraction, notes: [],
            detail: nil)
    }

    static func noteText(_ note: PlanNote) -> String {
        switch note {
        case .alphaFlattened: "Transparency was flattened onto white."
        case .firstFrameOnly: "Only the first frame or page was kept."
        case .svgRasterizedInPDF: "The drawing was saved as a picture inside the PDF."
        case .hdrToneMapped: "The HDR picture was saved in standard range."
        case .longGIF(let seconds): "Long clips make very large GIFs; this one is \(minutes(seconds))."
        case .sniffed(let format): sniffedText(format)
        }
    }

    /// Labels read with a leading vowel sound take "an": AVIF, AIFF, OGG, OPUS, and the letter names M and S.
    static let anLabels: Set<String> = ["AVIF", "AIFF", "AVI", "OGG", "OPUS", "MP3", "MP4", "M4A", "MKV", "SVG"]

    static func sniffedText(_ format: FormatID) -> String {
        let label = FormatRegistry.standard.format(format).wheelLabel
        return "This file is really \(anLabels.contains(label) ? "an" : "a") \(label); converted as \(label)."
    }

    /// "Saved to Downloads because the original folder is read-only." once per fallback folder that got a result.
    static func fallbackNotes(_ snapshot: BatchSnapshot) -> [String] {
        snapshot.items.filter { $0.state.published != nil }.compactMap(\.source?.fallbackFolder).uniqued().map {
            "Saved to \($0.lastPathComponent) because the original folder is read-only."
        }
    }

    /// Whole minutes, rounded, at least one: "1 minute", "3 minutes".
    static func minutes(_ seconds: Int) -> String {
        let count = max(Int((Double(seconds) / 60).rounded()), 1)
        return count == 1 ? "1 minute" : "\(count) minutes"
    }

    /// One public log line per finished batch, for example "1 saved, 0 failed, 0 cancelled" (no paths).
    public static func logLine(_ snapshot: BatchSnapshot) -> String {
        "\(snapshot.outputs.count) saved, \(snapshot.failures.count) failed, \(snapshot.cancelledCount) cancelled"
    }
}

import Foundation
import ZivletCore
import ZivletRuntime

/// Progress as the ring or the bar can draw it (19b §6.2): the fraction in whole steps of the drawn length, so a
/// change smaller than one step is not a change. Pure; no clock, no AppKit.
struct VisibleProgress: Sendable, Equatable {
    /// The most steps any island glyph gets: one per percent.
    static let maxSteps = 100

    let step: Int
    let steps: Int

    /// `fraction` is clamped to 0…1; a value that is not a number draws nothing.
    init(_ fraction: Double, steps: Int) {
        let count = max(1, steps)
        let clamped = fraction.isFinite ? min(1, max(0, fraction)) : 0
        self.steps = count
        step = Int((clamped * Double(count)).rounded(.down))
    }

    /// One step per device pixel of the drawn length, at most one per percent, at least one.
    static func steps(lengthInPoints: Double, scale: Double) -> Int {
        let pixels = (lengthInPoints * scale).rounded(.down)
        guard pixels.isFinite else { return 1 }
        return min(maxSteps, max(1, Int(pixels)))
    }
}

/// Everything about a batch that the island draws or speaks (19b §6.2): two snapshots with the same key look and read
/// the same, so the second one can stop before the board. Finishing, a failure, a new current file and a new percent
/// or time left always change it.
struct VisibleKey: Sendable, Equatable {
    let finished: Bool
    let outputs: Int
    let failures: Int
    let cancelled: Int
    let current: String?
    let index: Int?
    let count: Int
    let indeterminate: Bool
    /// The whole percent the text shows.
    let percent: Int?
    let ring: VisibleProgress?
    let bar: VisibleProgress?
    let timeLeft: String?
    /// "12.4 MB written" while the length is unknown.
    let written: String?

    init(_ snapshot: BatchSnapshot, ringSteps: Int, barSteps: Int) {
        let progress = snapshot.currentProgress
        let fraction = snapshot.isIndeterminate ? nil : snapshot.fraction
        finished = snapshot.isFinished
        outputs = snapshot.outputs.count
        failures = snapshot.failures.count
        cancelled = snapshot.cancelledCount
        current = snapshot.current?.item.name
        index = snapshot.current?.index
        count = snapshot.items.count
        indeterminate = snapshot.isIndeterminate
        percent = fraction.map { Int(($0 * 100).rounded(.down)) }
        ring = fraction.map { VisibleProgress($0, steps: ringSteps) }
        bar = fraction.map { VisibleProgress($0, steps: barSteps) }
        timeLeft = progress?.eta.map(HUDCopy.timeLeft)
        written =
            snapshot.isIndeterminate
            ? progress?.bytesWritten.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } : nil
    }
}

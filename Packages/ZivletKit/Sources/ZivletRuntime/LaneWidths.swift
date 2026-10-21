import Darwin
import Foundation
import ZivletEngineKit

/// Concurrency per scheduler lane (03a §4.2, 10 §8.1). Every width is at least 1.
public struct LaneWidths: Sendable, Equatable {
    public let widths: [Lane: Int]

    public init(_ widths: [Lane: Int]) {
        self.widths = widths.mapValues { max(1, $0) }
    }

    /// The 03a §4.2 table for a machine with `performanceCores` P-cores.
    public static func standard(performanceCores: Int = LaneWidths.performanceCores()) -> LaneWidths {
        let p = max(1, performanceCores)
        return LaneWidths([
            .cpu: p, .remux: 4, .audio: p, .hwVideo: 2, .swVideo: 1, .render: 1, .js: 2, .vision: 1, .metadata: 1,
            .office: 1, .iwork: 1,
        ])
    }

    public func width(_ lane: Lane) -> Int { widths[lane] ?? 1 }

    /// Memory pressure `.warning` (10 §8.1): every width halved, never below 1.
    public func halved() -> LaneWidths { LaneWidths(widths.mapValues { $0 / 2 }) }

    /// `hw.perflevel0.physicalcpu`, else the active processor count.
    public static func performanceCores() -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 else {
            return ProcessInfo.processInfo.activeProcessorCount
        }
        return Int(count)
    }
}

/// One semaphore per lane, created once; `apply` narrows or restores them for the current system load. Preparation
/// (probe and plan, before the lane is known) has its own gate: it may spawn a probe helper per job.
public struct LaneGates: Sendable {
    /// Probes running at once across all jobs; enough to keep the lanes fed, far below the descriptor limit.
    public static let preparationWidth = 4

    public let preparation = AsyncSemaphore(width: LaneGates.preparationWidth)
    private let base: LaneWidths
    private let semaphores: [Lane: AsyncSemaphore]

    public init(_ widths: LaneWidths) {
        base = widths
        semaphores = Dictionary(
            uniqueKeysWithValues: Lane.allCases.map { ($0, AsyncSemaphore(width: widths.width($0))) })
    }

    public func apply(_ load: SystemLoad) async {
        let limits = LaneLimits(base: base, load: load)
        for (lane, semaphore) in semaphores { await semaphore.setLimit(limits.limit(lane)) }
    }

    public func semaphore(for lane: Lane) -> AsyncSemaphore {
        guard let semaphore = semaphores[lane] else { preconditionFailure("every lane has a semaphore") }
        return semaphore
    }
}

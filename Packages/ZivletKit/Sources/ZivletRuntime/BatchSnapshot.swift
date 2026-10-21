import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// One row of a batch: a job, or a dropped item that was refused before it became one (`job == nil`).
public struct BatchItem: Sendable, Equatable {
    public let job: JobID?
    public let name: String
    public let state: JobState
    public let notes: [PlanNote]
    /// Its share of the batch's progress: the source size in bytes (10 §8.2), at least 1.
    public let weight: Double

    public init(job: JobID?, name: String, state: JobState, notes: [PlanNote] = [], weight: Double = 1) {
        self.job = job
        self.name = name
        self.state = state
        self.notes = notes
        self.weight = max(1, weight)
    }

    func with(state: JobState? = nil, notes: [PlanNote]? = nil) -> BatchItem {
        BatchItem(job: job, name: name, state: state ?? self.state, notes: notes ?? self.notes, weight: weight)
    }
}

/// Everything the HUD shows for one drop (03a §4.5), rebuilt from scheduler events by a pure reducer.
public struct BatchSnapshot: Sendable, Equatable {
    public let batch: BatchID
    public let target: FormatID
    public let items: [BatchItem]
    public let isFinished: Bool

    /// Refused items weigh as much as the smallest accepted file, so they count without dominating.
    public init(batch: BatchID, target: FormatID, plan: RequestPlan) {
        let refusedWeight = plan.requests.map { Double($0.input.byteCount) }.min() ?? 1
        self.init(
            batch: batch, target: target,
            items: plan.requests.map {
                BatchItem(job: $0.id, name: $0.input.fileName, state: .queued, weight: Double($0.input.byteCount))
            }
                + plan.rejections.map {
                    BatchItem(
                        job: nil, name: $0.url.lastPathComponent, state: .failed($0.error), weight: refusedWeight)
                },
            isFinished: false)
    }

    init(batch: BatchID, target: FormatID, items: [BatchItem], isFinished: Bool) {
        self.batch = batch
        self.target = target
        self.items = items
        self.isFinished = isFinished
    }

    public func applying(_ event: JobEvent) -> BatchSnapshot {
        switch event {
        case .changed(let batch, let job, let state) where batch == self.batch:
            return replacing(job) { $0.with(state: state) }
        case .noted(let batch, let job, let notes) where batch == self.batch:
            return replacing(job) { $0.with(notes: notes) }
        case .finished(let batch) where batch == self.batch:
            return BatchSnapshot(batch: batch, target: target, items: items, isFinished: true)
        default:
            return self
        }
    }

    private func replacing(_ job: JobID, _ change: (BatchItem) -> BatchItem) -> BatchSnapshot {
        BatchSnapshot(
            batch: batch, target: target, items: items.map { $0.job == job ? change($0) : $0 }, isFinished: isFinished)
    }

    public var outputs: [PublishedOutput] { items.compactMap(\.state.published) }

    public var failures: [(name: String, error: JobError)] {
        items.compactMap { item in
            guard case .failed(let error) = item.state else { return nil }
            return (item.name, error)
        }
    }

    public var cancelledCount: Int { items.count { $0.state == .cancelled } }
    public var doneCount: Int { items.count { $0.state.isTerminal } }

    /// Weighted mean of the items (weight = source bytes): finished = 1, running = its fraction (0 while
    /// indeterminate), otherwise 0. Monotonic because each item's state and fraction only move forward.
    public var fraction: Double {
        guard !items.isEmpty else { return 1 }
        let total = items.reduce(0.0) { $0 + $1.weight }
        let done = items.reduce(0.0) { sum, item in sum + item.weight * Self.share(item.state) }
        return min(1, done / total)
    }

    private static func share(_ state: JobState) -> Double {
        switch state {
        case .running(let progress): progress.fraction ?? 0
        case .verifying, .publishing: 1
        default: state.isTerminal ? 1 : 0
        }
    }

    /// The converting item's progress (stage, bytes, ETA), while it runs.
    public var currentProgress: JobProgress? {
        guard case .running(let progress) = current?.item.state else { return nil }
        return progress
    }

    /// The converting item's length is unknown: the HUD shows bytes and an indeterminate bar.
    public var isIndeterminate: Bool { currentProgress.map { $0.fraction == nil } ?? false }

    /// The item currently converting, for "name · 2 of 5".
    public var current: (index: Int, item: BatchItem)? {
        items.enumerated().first { !$0.element.state.isTerminal }.map { ($0.offset, $0.element) }
    }
}

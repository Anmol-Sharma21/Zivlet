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

    public init(job: JobID?, name: String, state: JobState, notes: [PlanNote] = []) {
        self.job = job
        self.name = name
        self.state = state
        self.notes = notes
    }

    func with(state: JobState? = nil, notes: [PlanNote]? = nil) -> BatchItem {
        BatchItem(job: job, name: name, state: state ?? self.state, notes: notes ?? self.notes)
    }
}

/// Everything the HUD shows for one drop (03a §4.5), rebuilt from scheduler events by a pure reducer.
public struct BatchSnapshot: Sendable, Equatable {
    public let batch: BatchID
    public let target: FormatID
    public let items: [BatchItem]
    public let isFinished: Bool

    public init(batch: BatchID, target: FormatID, plan: RequestPlan) {
        self.init(
            batch: batch, target: target,
            items: plan.requests.map { BatchItem(job: $0.id, name: $0.input.fileName, state: .queued) }
                + plan.rejections.map { BatchItem(job: nil, name: $0.url.lastPathComponent, state: .failed($0.error)) },
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

    /// Mean of the items: finished = 1, running = its fraction (0 while indeterminate), otherwise 0. Monotonic
    /// because each item's state only moves forward.
    public var fraction: Double {
        guard !items.isEmpty else { return 1 }
        let sum = items.reduce(0.0) { total, item in
            switch item.state {
            case .running(let progress): total + (progress.fraction ?? 0)
            case .verifying, .publishing: total + 1
            default: total + (item.state.isTerminal ? 1 : 0)
            }
        }
        return sum / Double(items.count)
    }

    /// The item currently converting, for "name · 2 of 5".
    public var current: (index: Int, item: BatchItem)? {
        items.enumerated().first { !$0.element.state.isTerminal }.map { ($0.offset, $0.element) }
    }
}

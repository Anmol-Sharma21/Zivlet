import Foundation
import ZivletCore
import ZivletEngineKit

/// Runs conversion jobs (P1-31, 03a §4.1–4.2, 4.6). Each job is its own task; a batch fails per file and keeps going.
/// Lanes bound concurrency per kind of work. Cancel reports `.cancelled` at once (03a §4.6: visible ≤ 100 ms); the
/// task then tears its helper down and removes its staging, and any later state it reports is dropped.
public actor JobScheduler {
    public nonisolated let events: AsyncStream<JobEvent>
    private let continuation: AsyncStream<JobEvent>.Continuation
    private let services: JobServices
    private var tasks: [JobID: Task<Void, Never>] = [:]
    private var batchOf: [JobID: BatchID] = [:]
    private var states: [JobID: JobState] = [:]
    private var remaining: [BatchID: Set<JobID>] = [:]

    public init(
        engines: [any Engine], publisher: Publisher = Publisher(), lanes: LaneWidths = .standard(),
        records: JobRecordStore? = JobRecordStore(), processes: any ProcessInspecting = SystemProcesses(),
        freeSpace: any FreeSpaceReading = VolumeFreeSpace(),
        clock: @escaping @Sendable () -> Duration = ProgressSink.uptime
    ) {
        (events, continuation) = AsyncStream.makeStream(of: JobEvent.self)
        services = JobServices(
            engines: engines, publisher: publisher, gates: LaneGates(lanes), records: records, processes: processes,
            freeSpace: freeSpace, clock: clock)
    }

    /// `batch` may be chosen by the caller, so it can prepare for the batch's events before submitting.
    @discardableResult
    public func submit(_ requests: [JobRequest], as batch: BatchID = BatchID()) -> BatchID {
        continuation.yield(.submitted(batch, requests))
        remaining[batch] = Set(requests.map(\.id))
        if requests.isEmpty { finishIfDone(batch) }
        for request in requests { start(request, in: batch) }
        return batch
    }

    /// Memory pressure and Low Power (03a §4.2): narrows the lanes for jobs not yet admitted.
    public func apply(_ load: SystemLoad) async {
        await services.gates.apply(load)
    }

    /// A job that is publishing is past the point of no return (a rename taking milliseconds), so cancel leaves it
    /// to succeed; otherwise the HUD would say "Cancelled" while the result sits on disk.
    public func cancel(job: JobID) {
        guard let batch = batchOf[job], let task = tasks[job], let state = states[job], !state.isTerminal,
            state != .publishing
        else { return }
        record(.cancelled, job: job, batch: batch)
        task.cancel()
    }

    public func cancel(batch: BatchID) {
        for job in remaining[batch] ?? [] { cancel(job: job) }
    }

    public func cancelAll() {
        for job in tasks.keys { cancel(job: job) }
    }

    /// Returns when every started job has finished its cleanup.
    public func waitUntilIdle() async {
        while let task = tasks.values.first { await task.value }
    }

    /// Quit (03a §4.2): cancel everything, wait up to `limit`. True when everything stopped in time. Polls rather
    /// than awaiting the tasks, because a job that ignores cancellation must not hold quit past the limit.
    public func shutdown(within limit: Duration) async -> Bool {
        cancelAll()
        let deadline = ContinuousClock.now + limit
        while !tasks.isEmpty {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: Self.shutdownPoll)
        }
        return true
    }

    static let shutdownPoll = Duration.milliseconds(10)

    private func start(_ request: JobRequest, in batch: BatchID) {
        let job = request.id
        batchOf[job] = batch
        record(.queued, job: job, batch: batch)
        let pipeline = JobPipeline(
            services: services, request: request,
            report: { state in await self.record(state, job: job, batch: batch) },
            beginPublishing: { await self.beginPublishing(job: job, batch: batch) },
            noted: { notes in await self.note(notes, job: job, batch: batch) })
        tasks[job] = Task {
            let final = await pipeline.run()
            self.complete(job, batch: batch, final: final)
        }
    }

    private func complete(_ job: JobID, batch: BatchID, final: JobState) {
        record(final, job: job, batch: batch)
        tasks[job] = nil
    }

    /// Cancel and publish are decided here, on the actor: whichever comes first wins. False when the job was
    /// already cancelled, so the pipeline discards its output instead of publishing it.
    private func beginPublishing(job: JobID, batch: BatchID) -> Bool {
        guard states[job]?.isTerminal != true else { return false }
        record(.publishing, job: job, batch: batch)
        return true
    }

    /// The single place states change: terminal states are final, progress never follows a later stage.
    private func record(_ state: JobState, job: JobID, batch: BatchID) {
        let current = states[job]
        if current?.isTerminal == true { return }
        if case .running = state, let current, !current.acceptsProgress { return }
        states[job] = state
        continuation.yield(.changed(batch, job, state))
        if state.isTerminal {
            remaining[batch]?.remove(job)
            finishIfDone(batch)
        }
    }

    private func note(_ notes: [PlanNote], job: JobID, batch: BatchID) {
        guard states[job]?.isTerminal != true else { return }
        continuation.yield(.noted(batch, job, notes))
    }

    private func finishIfDone(_ batch: BatchID) {
        guard remaining[batch]?.isEmpty == true else { return }
        remaining[batch] = nil
        continuation.yield(.finished(batch))
    }
}

extension JobState {
    /// Progress is shown only while a job is preparing or running.
    var acceptsProgress: Bool {
        switch self {
        case .queued, .preparing, .running: true
        default: false
        }
    }
}

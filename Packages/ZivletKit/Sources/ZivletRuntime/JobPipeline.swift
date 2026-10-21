import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit
import os

/// What the scheduler observes of a job.
public enum JobEvent: Sendable, Equatable {
    case submitted(BatchID, [JobRequest])
    case changed(BatchID, JobID, JobState)
    /// Plan notes for the result card ("Transparency flattened onto white").
    case noted(BatchID, JobID, [PlanNote])
    /// Every job of the batch reached a terminal state.
    case finished(BatchID)
}

/// The services one job uses; shared by all jobs of a scheduler.
struct JobServices: Sendable {
    let engines: [any Engine]
    let publisher: Publisher
    let gates: LaneGates
    let records: JobRecordStore?
    let processes: any ProcessInspecting
    let freeSpace: any FreeSpaceReading
    let clock: @Sendable () -> Duration
}

/// One job, Request → Probe → Plan → Admit → Execute → Verify → Publish (03a §4.1), each step producing one immutable
/// value. Every failure ends in a terminal state with the staging file and the job record removed.
struct JobPipeline: Sendable {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")

    let services: JobServices
    let request: JobRequest
    let report: @Sendable (JobState) async -> Void
    /// Moves the job to `.publishing` unless it was cancelled first; false means "do not publish".
    let beginPublishing: @Sendable () async -> Bool
    let noted: @Sendable ([PlanNote]) async -> Void

    /// `@concurrent`: the job runs on the global executor, never on the scheduler actor (02 §6.2).
    @concurrent func run() async -> JobState {
        await report(.preparing)
        var workspace: JobWorkspace?
        do {
            let engine = try selectEngine()
            try await checkAvailability(engine)
            try checkFreeSpace()
            let claimed = try services.publisher.claimStaging(for: request)
            workspace = claimed
            let record = JobRecord(job: request.id, ownerPID: getpid(), stagedFile: claimed.stagedFile)
            try services.records?.write(record)
            let published = try await convert(engine, workspace: claimed, record: record)
            services.records?.remove(request.id)
            return .succeeded(published)
        } catch {
            let isClean = workspace.map(cleanUp) ?? true
            if isClean { services.records?.remove(request.id) }
            return error == .cancelled ? .cancelled : .failed(error)
        }
    }

    /// What admission learned before the engine ran: the content overrode the extension (G-8).
    private var admissionNotes: [PlanNote] {
        request.input.namedFormat == nil ? [] : [.sniffed(request.input.format)]
    }

    /// The job already failed. A staging file that cannot be removed is logged and its job record kept, so the
    /// orphan reaper retries at the next launch. True when the staging is gone.
    private func cleanUp(_ workspace: JobWorkspace) -> Bool {
        do {
            try services.publisher.discard(workspace)
            return true
        } catch {
            Self.logger.error(
                "Staging not removed for job \(request.id, privacy: .public): \(error.logDescription, privacy: .public)"
            )
            return false
        }
    }

    private func convert(_ engine: any Engine, workspace: JobWorkspace, record: JobRecord) async throws(JobError)
        -> PublishedOutput
    {
        let plan = try await services.gates.preparation.withPermit { () async throws(JobError) in
            try await engine.prepare(request, workspace: workspace)
        }
        await noted(admissionNotes + plan.notes)
        let lane = plan.lanes.first ?? .cpu
        let output = try await services.gates.semaphore(for: lane).withPermit { () async throws(JobError) in
            try await JobSignposts.interval("execute") { () async throws(JobError) in
                try await execute(engine, plan: plan, record: record)
            }
        }
        await report(.verifying)
        try await JobSignposts.interval("verify") { () async throws(JobError) in
            try await engine.verify(output, plan: plan)
        }
        guard await beginPublishing() else { throw .cancelled }
        return try JobSignposts.interval("publish") { () throws(JobError) in
            try services.publisher.publish(output, for: request)
        }
    }

    /// Progress travels through an ordered stream and is drained before `execute` returns, so the scheduler never
    /// sees a progress update after the job moved on to verification.
    private func execute(_ engine: any Engine, plan: ExecutionPlan, record: JobRecord) async throws(JobError)
        -> StagedOutput
    {
        let (updates, feed) = AsyncStream.makeStream(of: JobProgress.self)
        let report = self.report
        let forwarder = Task { for await update in updates { await report(.running(update)) } }
        let sink = ProgressSink(clock: services.clock) { feed.yield($0) }
        sink.report(0)
        let limit = DiskPreflight.outputLimit(freeBytes: services.freeSpace.freeBytes(at: request.destination))
        let context = ExecutionContext(progress: sink, spawned: spawnRecorder(record), outputByteLimit: limit)
        let result: Result<StagedOutput, JobError>
        do {
            result = .success(try await engine.execute(plan, context: context))
        } catch {
            result = .failure(error)
        }
        feed.finish()
        await forwarder.value
        return try result.get()
    }

    /// Adds the helper's PID and executable path to the job record (orphan reaper input).
    private func spawnRecorder(_ record: JobRecord) -> @Sendable (Int32) -> Void {
        let services = self.services
        return { pid in
            do {
                try services.records?.write(
                    record.with(
                        childPID: pid, childPath: services.processes.executablePath(pid),
                        childStart: services.processes.startTime(pid)))
            } catch {
                Self.logger.error("Job record not updated: \(String(describing: error), privacy: .private)")
            }
        }
    }

    private func selectEngine() throws(JobError) -> any Engine {
        guard let engine = services.engines.first(where: { $0.handles(request.pair) }) else {
            throw .pairNotSupported(request.input.format, request.target)
        }
        return engine
    }

    /// M3 estimates the output at the source's size (index D-M3-13); the 512 MB reserve covers growth such as
    /// MP3 → WAV until plans carry their own estimates.
    private func checkFreeSpace() throws(JobError) {
        try DiskPreflight.check(
            estimatedBytes: request.input.byteCount, freeBytes: services.freeSpace.freeBytes(at: request.destination))
    }

    private func checkAvailability(_ engine: any Engine) async throws(JobError) {
        if case .unavailable(let missing) = await engine.availability(of: request.pair) {
            throw .routeUnavailable(request.input.format, request.target, missing)
        }
    }
}

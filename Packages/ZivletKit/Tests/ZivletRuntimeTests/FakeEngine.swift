import Foundation
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// A scripted engine: plans one stage on `lane`, runs `body`, writes "out" into the staged file, verifies as told.
struct FakeEngine: Engine {
    typealias Body = @Sendable (ExecutionPlan, ExecutionContext) async throws(JobError) -> Void

    let id = EngineID.image
    var lane: Lane = .cpu
    var availability: RouteAvailability = .available
    var prepareError: JobError?
    var verifyError: JobError?
    var notes: [PlanNote] = []
    var body: Body = { _, _ throws(JobError) in }
    /// After `body` so trailing closures still bind to `body`.
    var onPrepare: @Sendable () async -> Void = {}

    func handles(_ pair: ConversionPair) -> Bool { pair.source != .mp3 }

    func availability(of pair: ConversionPair) async -> RouteAvailability { availability }

    func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        await onPrepare()
        if let prepareError { throw prepareError }
        do {
            return try ExecutionPlan(
                engine: id, stages: [.ffmpeg(FFmpegStage(argv: ["fake"], expectedDurationMicros: nil))],
                stageWeights: [1], lanes: [lane], outputFormat: request.target, stagedFile: workspace.stagedFile,
                notes: notes)
        } catch {
            throw .internalInvariant("fake plan")
        }
    }

    func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        try await body(plan, context)
        do {
            try Data("out".utf8).write(to: plan.stagedFile)
        } catch {
            throw .diskFull
        }
        return StagedOutput(format: plan.outputFormat, url: plan.stagedFile, byteCount: 3)
    }

    func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        if let verifyError { throw verifyError }
    }

    /// Sleeps until the job is cancelled, then throws like a torn-down helper would.
    static let waitsForCancel: Body = { _, _ throws(JobError) in
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        throw .cancelled
    }
}

extension JobScheduler {
    /// Every event up to and including `.finished(batch)`.
    func collect(until batch: BatchID) async -> [JobEvent] {
        var seen: [JobEvent] = []
        for await event in events {
            seen.append(event)
            if event == .finished(batch) { break }
        }
        return seen
    }
}

extension [JobEvent] {
    /// States of one job, in order.
    func states(of job: JobID) -> [JobState] {
        compactMap { event in
            guard case .changed(_, let id, let state) = event, id == job else { return nil }
            return state
        }
    }
}

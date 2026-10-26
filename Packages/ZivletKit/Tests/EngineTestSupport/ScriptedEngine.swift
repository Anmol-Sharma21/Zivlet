import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit

/// A one-shot signal: `wait()` returns once `fire()` has been called (before or after the wait began).
public final class Signal: Sendable {
    private let state = Mutex<(fired: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, []))

    public init() {}

    public func fire() {
        let waiters = state.withLock { state in
            state.fired = true
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }

    public var hasFired: Bool { state.withLock(\.fired) }

    public func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state in
                if !state.fired { state.waiters.append(continuation) }
                return state.fired
            }
            if resumeNow { continuation.resume() }
        }
    }
}

/// A thread-safe count.
public final class Counter: Sendable {
    private let count = Mutex(0)

    public init() {}

    public var value: Int { count.withLock { $0 } }

    @discardableResult
    public func increment() -> Int {
        count.withLock {
            $0 += 1
            return $0
        }
    }
}

/// A scripted engine for worker and connection tests: plans one stage writing the workspace's staged file, then
/// executes as told. `reachedExecute` fires when `execute` starts; `executeCount` counts the runs.
public struct ScriptedEngine: Engine {
    public enum Execution: Sendable {
        case succeed
        /// Reports 0.5 and then 1.0 before it writes the output.
        case reportProgress
        /// Reports a child PID through the context, then succeeds.
        case spawn(Int32)
        case waitUntilCancelled
        case fail(JobError)
    }

    public let id: EngineID
    public let execution: Execution
    public let reachedExecute = Signal()
    private let runs = Counter()

    public init(id: EngineID = .image, execution: Execution = .succeed) {
        self.id = id
        self.execution = execution
    }

    public var executeCount: Int { runs.value }

    public func handles(_ pair: ConversionPair) -> Bool { pair.source == .png }

    public func availability(of pair: ConversionPair) async -> RouteAvailability {
        pair.target == .webp ? .unavailable(["libwebp"]) : .available
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        try Self.plan(engine: id, target: request.target, staged: workspace.stagedFile)
    }

    public static func plan(engine: EngineID = .image, target: FormatID = .jpg, staged: URL) throws(JobError)
        -> ExecutionPlan
    {
        do {
            return try ExecutionPlan(
                engine: engine, stages: [.ffmpeg(FFmpegStage(argv: ["scripted"], expectedDurationMicros: nil))],
                stageWeights: [1], lanes: [.cpu], outputFormat: target, stagedFile: staged)
        } catch {
            throw .internalInvariant("scripted plan")
        }
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        runs.increment()
        reachedExecute.fire()
        switch execution {
        case .succeed: break
        case .reportProgress:
            context.progress.report(0.5)
            context.progress.report(1)
        case .spawn(let pid): context.spawned(pid)
        case .waitUntilCancelled:
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
            throw .cancelled
        case .fail(let error): throw error
        }
        do {
            try Data("out".utf8).write(to: plan.stagedFile)
        } catch {
            throw .writeFailed("scripted")
        }
        return StagedOutput(format: plan.outputFormat, url: plan.stagedFile, byteCount: 3)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        guard output.byteCount > 0 else { throw .verificationFailed("empty") }
    }
}

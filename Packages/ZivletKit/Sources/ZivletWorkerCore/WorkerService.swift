import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import os

/// The worker's logic, free of XPC (P2-01, plan 18c C3): every request is validated (`WorkerRequestValidator`),
/// then answered by a hosted engine. `execute` and `prepare` run in a child task kept by job id, so `cancel(job)`
/// stops them; progress and spawned PIDs go out as events while the step runs, always before its reply. Every
/// engine error comes back as `.failed(JobError)`. The idle timer is disarmed while any request is being handled
/// and armed again when the last one ends (D-M6-10).
public actor WorkerService {
    public typealias EventSink = @Sendable (WorkerEvent) -> Void
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    public static let osBuild = CapabilityProbe.currentOSBuild()

    private let engines: [any Engine]
    private let validator: WorkerRequestValidator
    private let idle: IdleTimer
    private let onSelfKill: @Sendable (Int) -> Void
    private var jobs: [JobID: Task<WorkerReply, Never>] = [:]
    private var handling = 0

    /// `onSelfKill` serves the DEBUG smoke request only; the worker's main passes a SIGKILL of its own process.
    public init(
        engines: [any Engine], idleAfter: Duration = .seconds(60),
        sleep: @escaping IdleTimer.Sleeper = IdleTimer.realSleep,
        onIdle: @escaping @Sendable () -> Void, onSelfKill: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.engines = engines
        validator = WorkerRequestValidator(hostedEngines: Set(engines.map(\.id)))
        idle = IdleTimer(after: idleAfter, sleep: sleep, onIdle: onIdle)
        self.onSelfKill = onSelfKill
        idle.arm()
    }

    /// The jobs whose step is running now.
    public var runningJobs: Set<JobID> { Set(jobs.keys) }

    public func handle(_ request: WorkerRequest, events: @escaping EventSink) async -> WorkerReply {
        begin()
        defer { end() }
        do {
            try validator.validate(request)
        } catch {
            Self.logger.error("Request refused: \(error.logDescription, privacy: .public)")
            return .failed(error)
        }
        return await answer(request, events: events)
    }

    private func answer(_ request: WorkerRequest, events: @escaping EventSink) async -> WorkerReply {
        switch request {
        case .ping: return .pong(pid: getpid(), osBuild: Self.osBuild)
        case .capabilities: return .capabilities(await capabilities())
        case .prepare(let job, let workspace):
            guard let engine = engines.first(where: { $0.handles(job.pair) }) else {
                return .failed(.pairNotSupported(job.input.format, job.target))
            }
            return await track(job.id) { await Self.prepare(engine, job, workspace) }
        case .execute(let job, let plan, let limit):
            guard let engine = engine(plan.engine) else { return .failed(.engineMissing(plan.engine)) }
            return await track(job) { await Self.execute(engine, plan, job: job, limit: limit, events: events) }
        case .verify(let output, let plan):
            guard let engine = engine(plan.engine) else { return .failed(.engineMissing(plan.engine)) }
            return await Self.verify(engine, output, plan)
        case .cancel(let job):
            jobs[job]?.cancel()
            return .accepted
        #if DEBUG
            case .selfKillForTesting(let milliseconds):
                onSelfKill(milliseconds)
                return .accepted
            case .setIdleForTesting(let seconds):
                idle.setInterval(.seconds(seconds))
                return .accepted
        #endif
        }
    }

    private func engine(_ id: EngineID) -> (any Engine)? { engines.first { $0.id == id } }

    /// Runs one step in a child task kept under `job`, so a cancel request can reach it.
    private func track(_ job: JobID, _ step: @escaping @Sendable () async -> WorkerReply) async -> WorkerReply {
        let task = Task { await step() }
        jobs[job] = task
        let reply = await task.value
        jobs[job] = nil
        return reply
    }

    private func begin() {
        handling += 1
        idle.disarm()
    }

    private func end() {
        handling -= 1
        if handling == 0 { idle.arm() }
    }

    /// Every catalog route each engine handles, with its availability on this Mac.
    private func capabilities() async -> WorkerCapabilities {
        var entries: [EngineCapability] = []
        for engine in engines {
            var routes: [RouteCapability] = []
            for pair in ConversionCatalog.standard.pairs where engine.handles(pair) {
                routes.append(RouteCapability(pair: pair, availability: await engine.availability(of: pair)))
            }
            entries.append(EngineCapability(id: engine.id, routes: routes))
        }
        return WorkerCapabilities(engines: entries)
    }

    @concurrent private static func prepare(_ engine: any Engine, _ job: JobRequest, _ workspace: JobWorkspace) async
        -> WorkerReply
    {
        do {
            return .planned(try await engine.prepare(job, workspace: workspace))
        } catch {
            return .failed(error)
        }
    }

    @concurrent private static func execute(
        _ engine: any Engine, _ plan: ExecutionPlan, job: JobID, limit: Int64?, events: @escaping EventSink
    ) async -> WorkerReply {
        let sink = ProgressSink { events(.progress(job, $0)) }
        let context = ExecutionContext(progress: sink, spawned: { events(.spawned(job, $0)) }, outputByteLimit: limit)
        do {
            return .staged(try await engine.execute(plan, context: context))
        } catch {
            return .failed(error)
        }
    }

    @concurrent private static func verify(_ engine: any Engine, _ output: StagedOutput, _ plan: ExecutionPlan) async
        -> WorkerReply
    {
        do {
            try await engine.verify(output, plan: plan)
            return .verified
        } catch {
            return .failed(error)
        }
    }
}

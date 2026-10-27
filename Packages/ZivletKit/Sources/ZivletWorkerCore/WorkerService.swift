import Darwin
import EngineVision
import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import os

/// The worker's logic, free of XPC (P2-01, plan 18c C3): every request is validated (`WorkerRequestValidator`),
/// then answered by a hosted engine. `execute`, `prepare`, text jobs and the text warm-up run in a child task kept by
/// job id and the session that sent it, so `cancel(job)` and the end of that session stop them and nothing else: a
/// retry reuses its job id on a new session (G-M6-21). A cancel can be handled before its request (they are separate
/// messages), so a cancel for a job that is not running is remembered for its session and the job, when it comes, is
/// answered as cancelled without starting. Progress and spawned PIDs go out as events while the step runs; they are
/// best-effort and may reach the app after the reply. Every engine error comes back as `.failed(JobError)`. The idle
/// timer is disarmed while any request is being handled and armed again when the last one ends (D-M6-10).
public actor WorkerService {
    public typealias EventSink = @Sendable (WorkerEvent) -> Void
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    public static let osBuild = CapabilityProbe.currentOSBuild()

    private let engines: [any Engine]
    private let text: TextReader?
    private let validator: WorkerRequestValidator
    private let idle: IdleTimer
    private let onSelfKill: @Sendable (Int) -> Void
    private struct Step: Hashable {
        let session: WorkerSessionID
        let job: JobID
    }

    private var jobs: [Step: Task<WorkerReply, Never>] = [:]
    /// Cancels that came before their job, oldest first; bounded, since a cancel can also come after its job ended.
    private var cancelledEarly: [Step] = []
    static let rememberedCancels = 64
    private var handling = 0

    /// `text` hosts Copy Text (nil: text requests are refused as `.engineMissing(.vision)`). `onSelfKill` serves the
    /// DEBUG smoke request only; the worker's main passes a SIGKILL of its own process.
    public init(
        engines: [any Engine], text: TextReader? = nil, idleAfter: Duration = .seconds(60),
        sleep: @escaping IdleTimer.Sleeper = IdleTimer.realSleep,
        onIdle: @escaping @Sendable () -> Void, onSelfKill: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.engines = engines
        self.text = text
        let hosted = Set(engines.map(\.id)).union(text == nil ? [] : [.vision])
        validator = WorkerRequestValidator(hostedEngines: hosted)
        idle = IdleTimer(after: idleAfter, sleep: sleep, onIdle: onIdle)
        self.onSelfKill = onSelfKill
        idle.arm()
    }

    /// The app ended `session`: nothing will read its jobs' replies, and its early cancels have nothing left to stop.
    public func endSession(_ session: WorkerSessionID) {
        for (step, task) in jobs where step.session == session { task.cancel() }
        cancelledEarly.removeAll { $0.session == session }
    }

    /// The jobs whose step is running now, in any session.
    public var runningJobs: Set<JobID> { Set(jobs.keys.map(\.job)) }

    public func handle(
        _ request: WorkerRequest, session: WorkerSessionID = .single, events: @escaping EventSink
    ) async -> WorkerReply {
        begin()
        defer { end() }
        do {
            try validator.validate(request)
        } catch {
            Self.logger.error("Request refused: \(error.logDescription, privacy: .public)")
            return .failed(error)
        }
        return await answer(request, session: session, events: events)
    }

    private func answer(_ request: WorkerRequest, session: WorkerSessionID, events: @escaping EventSink) async
        -> WorkerReply
    {
        switch request {
        case .ping: return .pong(pid: getpid(), osBuild: Self.osBuild)
        case .capabilities: return .capabilities(await capabilities())
        case .prepare(let job, let workspace):
            guard let engine = engines.first(where: { $0.handles(job.pair) }) else {
                return .failed(.pairNotSupported(job.input.format, job.target))
            }
            return await track(Step(session: session, job: job.id), cancelled: .failed(.cancelled)) {
                await Self.prepare(engine, job, workspace)
            }
        case .execute(let job, let plan, let limit):
            guard let engine = engine(plan.engine) else { return .failed(.engineMissing(plan.engine)) }
            return await track(Step(session: session, job: job), cancelled: .failed(.cancelled)) {
                await Self.execute(engine, plan, job: job, limit: limit, events: events)
            }
        case .verify(let output, let plan):
            guard let engine = engine(plan.engine) else { return .failed(.engineMissing(plan.engine)) }
            return await Self.verify(engine, output, plan)
        case .cancel(let job):
            cancel(Step(session: session, job: job))
            return .accepted
        case .recognizeText, .textCapabilities, .warmUpText:
            guard let text else { return .failed(.engineMissing(.vision)) }
            return await answerText(request, session: session, reader: text, events: events)
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

    /// Text jobs and the warm-up run as tracked steps (so cancel and the session's end reach them); the warm-up at
    /// `.utility` (D-M6-16).
    private func answerText(
        _ request: WorkerRequest, session: WorkerSessionID, reader: TextReader, events: @escaping EventSink
    ) async -> WorkerReply {
        switch request {
        case .recognizeText(let job):
            return await track(Step(session: session, job: job.id), cancelled: .textFailed(.cancelled)) {
                await Self.recognize(job, reader: reader, events: events)
            }
        case .warmUpText(let id, let languages):
            let step = Step(session: session, job: id)
            return await track(step, cancelled: .textFailed(.cancelled), priority: .utility) {
                await Self.warmUp(languages, reader: reader)
            }
        default:
            return .textCapabilities(reader.currentCapabilities)
        }
    }

    @concurrent private static func warmUp(_ languages: [LanguageTag], reader: TextReader) async -> WorkerReply {
        do {
            try await reader.warmUp(languages)
            return .accepted
        } catch {
            logger.error("Text warm-up stopped: \(error.logDescription, privacy: .public)")
            return .textFailed(error)
        }
    }

    @concurrent private static func recognize(_ job: TextJob, reader: TextReader, events: @escaping EventSink) async
        -> WorkerReply
    {
        do {
            let text = try await reader.read(job) { events(.progress(job.id, JobProgress(fraction: $0))) }
            for file in text.skipped {
                logger.error("Text job skipped a file: \(file.error.logDescription, privacy: .public)")
            }
            return .text(text)
        } catch {
            logger.error("Text job failed: \(error.logDescription, privacy: .public)")
            return .textFailed(error)
        }
    }

    /// Runs one step in a child task kept under `job`, so a cancel request can reach it; a job cancelled before it
    /// came never starts and gets `cancelled` back.
    private func track(
        _ key: Step, cancelled: WorkerReply, priority: TaskPriority? = nil,
        _ step: @escaping @Sendable () async -> WorkerReply
    ) async -> WorkerReply {
        if let early = cancelledEarly.firstIndex(of: key) {
            cancelledEarly.remove(at: early)
            return cancelled
        }
        let task = Task(priority: priority) { await step() }
        jobs[key] = task
        let reply = await task.value
        jobs[key] = nil
        return reply
    }

    /// Stops the step when it runs, else remembers the cancel for when it comes.
    private func cancel(_ key: Step) {
        if let task = jobs[key] { return task.cancel() }
        cancelledEarly = Array((cancelledEarly + [key]).suffix(Self.rememberedCancels))
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

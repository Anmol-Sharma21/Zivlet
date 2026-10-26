import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import os

/// Where conversions run, for Diagnostics and the log: never paths.
public enum WorkerStatus: Sendable, Equatable {
    case notStarted
    case running(pid: Int32)
    case inProcess(reason: String)

    public var line: String {
        switch self {
        case .notStarted: "Worker: not started yet"
        case .running(let pid): "Worker: running (pid \(pid))"
        case .inProcess(let reason): "Worker: in-process (\(reason))"
        }
    }
}

/// The worker, or the reason it is not used.
public enum WorkerChoice: Sendable {
    case worker(WorkerConnection, WorkerCapabilities)
    case inProcess(reason: String)
}

/// Chooses once per launch, lazily at the first job (never at launch), whether conversions run in the worker
/// (D-M6-9): the worker bundle must exist, pass its signature check, and answer a ping within the timeout; otherwise
/// the in-process engines run, and the reason is logged once. A worker that crashes later is never replaced by the
/// in-process engine (a file that crashes the worker would crash the app).
public actor WorkerSelection {
    public typealias Sleeper = @Sendable (Duration) async -> Void
    public static let pingTimeout = Duration.seconds(30)
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")

    private let workerBundle: URL?
    private let verify: @Sendable (URL) throws(JobError) -> Void
    private let connection: WorkerConnection
    private let timeout: Duration
    private let sleep: Sleeper
    private var decided: WorkerChoice?
    private var deciding: Task<WorkerChoice, Never>?
    public private(set) var status = WorkerStatus.notStarted

    public init(
        workerBundle: URL?, verify: @escaping @Sendable (URL) throws(JobError) -> Void, connection: WorkerConnection,
        timeout: Duration = WorkerSelection.pingTimeout,
        sleep: @escaping Sleeper = { duration in try? await Task.sleep(for: duration) }
    ) {
        self.workerBundle = workerBundle
        self.verify = verify
        self.connection = connection
        self.timeout = timeout
        self.sleep = sleep
    }

    /// The worker connection whatever the choice, so quit can close it.
    public nonisolated var workerConnection: WorkerConnection { connection }

    public func choice() async -> WorkerChoice {
        if let decided { return decided }
        if let deciding { return await deciding.value }
        let task = Task { await self.decide() }
        deciding = task
        let choice = await task.value
        decided = choice
        return choice
    }

    private func decide() async -> WorkerChoice {
        guard let bundle = workerBundle, FileManager.default.fileExists(atPath: bundle.path) else {
            return inProcess("worker missing")
        }
        do {
            try verify(bundle)
        } catch {
            return inProcess("worker damaged")
        }
        guard let (pid, capabilities) = await reachWorker() else { return inProcess("worker unreachable") }
        status = .running(pid: pid)
        Self.logger.notice("Worker ready: pid \(pid, privacy: .public), app pid \(getpid(), privacy: .public)")
        return .worker(connection, capabilities)
    }

    private func inProcess(_ reason: String) -> WorkerChoice {
        status = .inProcess(reason: reason)
        Self.logger.error("Conversions run in-process: \(reason, privacy: .public)")
        return .inProcess(reason: reason)
    }

    /// Ping and capabilities, or nil when they fail or the timeout passes first.
    private func reachWorker() async -> (Int32, WorkerCapabilities)? {
        let connection = self.connection
        let (timeout, sleep) = (self.timeout, self.sleep)
        return await withCheckedContinuation { continuation in
            let once = Mutex(Optional(continuation))
            let finish: @Sendable ((Int32, WorkerCapabilities)?) -> Void = { result in
                once.withLock { pending in
                    defer { pending = nil }
                    return pending
                }?.resume(returning: result)
            }
            Task {
                do {
                    let pong = try await connection.ping()
                    finish((pong.pid, try await connection.capabilities()))
                } catch {
                    finish(nil)
                }
            }
            Task {
                await sleep(timeout)
                finish(nil)
            }
        }
    }
}

/// An `Engine` that answers `handles` and `availability` from the in-process engine (no worker launch for the
/// wheel's capability snapshot) and runs `prepare`, `execute` and `verify` where `WorkerSelection` chose.
public struct WorkerRoutedEngine: Engine {
    let local: any Engine
    let selection: WorkerSelection

    public init(local: any Engine, selection: WorkerSelection) {
        self.local = local
        self.selection = selection
    }

    public var id: EngineID { local.id }

    public func handles(_ pair: ConversionPair) -> Bool { local.handles(pair) }

    public func availability(of pair: ConversionPair) async -> RouteAvailability {
        await local.availability(of: pair)
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        try await chosen().prepare(request, workspace: workspace)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        try await chosen().execute(plan, context: context)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        try await chosen().verify(output, plan: plan)
    }

    private func chosen() async -> any Engine {
        guard case .worker(let connection, let capabilities) = await selection.choice(),
            let capability = capabilities.engine(local.id)
        else { return local }
        return RemoteEngine(capability: capability, connection: connection)
    }
}

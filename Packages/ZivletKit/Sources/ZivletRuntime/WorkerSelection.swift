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

/// Chooses lazily at the first job (never at launch) whether conversions run in the worker (D-M6-9): the worker
/// bundle must exist, pass its signature check, and answer a ping within the timeout; otherwise the in-process engines
/// run, and the reason is logged with its cause. A missing or damaged worker is final for the launch; an unreachable
/// one (a slow cold start under load) is tried again at the first job after `retryUnreachableAfter`, on a new session.
/// A worker that crashes later is never replaced by the in-process engine (a file that crashes the worker would crash
/// the app).
public actor WorkerSelection {
    public typealias Sleeper = @Sendable (Duration) async -> Void
    public static let pingTimeout = Duration.seconds(30)
    public static let retryUnreachable = Duration.seconds(60)
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")

    private let workerBundle: URL?
    private let verify: @Sendable (URL) throws(JobError) -> Void
    private let connection: WorkerConnection
    private let timeout: Duration
    private let sleep: Sleeper
    private let retryUnreachableAfter: Duration
    private var decided: WorkerChoice?
    /// When the last decision found the worker unreachable; nil otherwise.
    private var unreachableSince: ContinuousClock.Instant?
    private var deciding: Task<WorkerChoice, Never>?
    public private(set) var status = WorkerStatus.notStarted

    public init(
        workerBundle: URL?, verify: @escaping @Sendable (URL) throws(JobError) -> Void, connection: WorkerConnection,
        timeout: Duration = WorkerSelection.pingTimeout,
        sleep: @escaping Sleeper = { duration in try? await Task.sleep(for: duration) },
        retryUnreachableAfter: Duration = WorkerSelection.retryUnreachable
    ) {
        self.workerBundle = workerBundle
        self.verify = verify
        self.connection = connection
        self.timeout = timeout
        self.sleep = sleep
        self.retryUnreachableAfter = retryUnreachableAfter
    }

    /// `Contents/XPCServices/ZivletWorker.xpc` inside an app bundle.
    public static func workerBundle(in app: URL) -> URL {
        app.appending(path: "Contents/XPCServices/ZivletWorker.xpc", directoryHint: .isDirectory)
    }

    /// The running app's worker: inside its bundle, signature-checked like a helper (P1-50), reached over XPC with
    /// the peer requirement from the app's own signature (D-M6-7).
    public static func standard(bundle: Bundle = .main) -> WorkerSelection {
        let requirement = WorkerPeerPolicy.requirement(own: .current(), peer: WorkerPeerPolicy.workerIdentifier)
        return WorkerSelection(
            workerBundle: workerBundle(in: bundle.bundleURL),
            verify: { url throws(JobError) in try HelperIntegrity.check(url, policy: .current(), engine: .worker) },
            connection: WorkerConnection(transport: XPCSessionFactory(requirement: requirement)))
    }

    /// The worker connection whatever the choice, so quit can close it.
    public nonisolated var workerConnection: WorkerConnection { connection }

    public func choice() async -> WorkerChoice {
        if let decided, !retriesNow { return decided }
        if let deciding { return await deciding.value }
        let task = Task { await self.decide() }
        deciding = task
        let choice = await task.value
        deciding = nil
        decided = choice
        return choice
    }

    /// The last decision found the worker unreachable long enough ago to try again.
    private var retriesNow: Bool {
        guard let unreachableSince else { return false }
        return ContinuousClock.now - unreachableSince >= retryUnreachableAfter
    }

    private func decide() async -> WorkerChoice {
        unreachableSince = nil
        guard let bundle = workerBundle, FileManager.default.fileExists(atPath: bundle.path) else {
            return inProcess("worker missing", cause: "no bundle")
        }
        do {
            try verify(bundle)
        } catch {
            return inProcess("worker damaged", cause: error.logDescription)
        }
        switch await reachWorker() {
        case .failure(let failure):
            unreachableSince = ContinuousClock.now
            connection.reset()  // the next try opens a new session instead of waiting on this one
            return inProcess("worker unreachable", cause: failure.logDescription)
        case .success(let (pid, capabilities)):
            status = .running(pid: pid)
            Self.logger.notice("Worker ready: pid \(pid, privacy: .public), app pid \(getpid(), privacy: .public)")
            return .worker(connection, capabilities)
        }
    }

    private func inProcess(_ reason: String, cause: String) -> WorkerChoice {
        status = .inProcess(reason: reason)
        Self.logger.error("Conversions run in-process: \(reason, privacy: .public) (\(cause, privacy: .public))")
        return .inProcess(reason: reason)
    }

    /// Why the worker did not answer: its error, or the timeout.
    enum ReachFailure: Error {
        case failed(JobError)
        case timedOut

        var logDescription: String {
            switch self {
            case .failed(let error): error.logDescription
            case .timedOut: "no answer within the timeout"
            }
        }
    }

    /// Ping and capabilities, or why not. The timer is cancelled when the worker answers; a ping that outlives the
    /// timeout cannot be stopped (XPC replies are not cancellable) and ends with its session.
    private func reachWorker() async -> Result<(Int32, WorkerCapabilities), ReachFailure> {
        let connection = self.connection
        let (timeout, sleep) = (self.timeout, self.sleep)
        return await withCheckedContinuation { continuation in
            let once = Mutex(Optional(continuation))
            let finish: @Sendable (Result<(Int32, WorkerCapabilities), ReachFailure>) -> Void = { result in
                once.withLock { pending in
                    defer { pending = nil }
                    return pending
                }?.resume(returning: result)
            }
            let timer = Task {
                await sleep(timeout)
                finish(.failure(.timedOut))
            }
            Task {
                do throws(JobError) {
                    let pong = try await connection.ping()
                    finish(.success((pong.pid, try await connection.capabilities())))
                } catch {
                    finish(.failure(.failed(error)))
                }
                timer.cancel()
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

import EngineVision
import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import os

/// The app's side of the worker (P2-01, 02 §7.4, D-M6-2). It opens a session lazily at the first call and keeps it.
/// A session that ends with calls in flight fails each of them with `.workerCrashed` (the channel's contract) and is
/// dropped and closed, so the next call opens a new one; a session the worker ends while idle fails nothing. After
/// `close()` (quit) no call opens a session again: each throws `.cancelled`. Events are routed by job to the context
/// of the call that runs it, in order among themselves; they are best-effort, since XPC does not order them against
/// the step's reply, and one that comes after the reply is dropped (the reply carries the outcome). A cancelled Swift
/// task sends `.cancel(job)` on the session its request went to, never on a new one; the worker remembers a cancel
/// that overtakes its request.
public final class WorkerConnection: Sendable {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")

    private struct Session {
        let id: Int
        let channel: any WorkerChannel
    }

    private struct State {
        var session: Session?
        var opened = 0
        var closed = false
        var routes: [JobID: ExecutionContext] = [:]
    }

    private let transport: any WorkerTransport
    private let state = Mutex(State())
    private let opening = Mutex(())

    public init(transport: any WorkerTransport) {
        self.transport = transport
    }

    public func ping() async throws(JobError) -> (pid: Int32, osBuild: String) {
        guard case .pong(let pid, let osBuild) = try await send(.ping) else { throw Self.unexpected("ping") }
        return (pid, osBuild)
    }

    public func capabilities() async throws(JobError) -> WorkerCapabilities {
        guard case .capabilities(let capabilities) = try await send(.capabilities) else {
            throw Self.unexpected("capabilities")
        }
        return capabilities
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        guard case .planned(let plan) = try await cancellable(.prepare(request, workspace), job: request.id) else {
            throw Self.unexpected("prepare")
        }
        return plan
    }

    public func execute(_ plan: ExecutionPlan, job: JobID, context: ExecutionContext) async throws(JobError)
        -> StagedOutput
    {
        state.withLock { $0.routes[job] = context }
        defer { _ = state.withLock { $0.routes.removeValue(forKey: job) } }
        let request = WorkerRequest.execute(job, plan, outputByteLimit: context.outputByteLimit)
        guard case .staged(let output) = try await cancellable(request, job: job) else {
            throw Self.unexpected("execute")
        }
        return output
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        guard case .verified = try await send(.verify(output, plan)) else { throw Self.unexpected("verify") }
    }

    /// A Copy Text job (P2-104). Transport failures throw (`.workerCrashed` among them, for the caller's retry);
    /// the worker's own outcome is the result. Progress arrives unthrottled and in order, best-effort.
    public func recognizeText(_ job: TextJob, progress: @escaping @Sendable (Double) -> Void) async throws(JobError)
        -> Result<RecognizedText, TextError>
    {
        let sink = ProgressSink(interval: .zero) { progress($0.fraction ?? 0) }
        state.withLock { $0.routes[job.id] = ExecutionContext(progress: sink) }
        defer { _ = state.withLock { $0.routes.removeValue(forKey: job.id) } }
        switch try await cancellable(.recognizeText(job), job: job.id) {
        case .text(let text): return .success(text)
        case .textFailed(let error): return .failure(error)
        default: throw Self.unexpected("recognizeText")
        }
    }

    public func textCapabilities() async throws(JobError) -> Result<VisionCapabilities, TextError> {
        switch try await send(.textCapabilities) {
        case .textCapabilities(let capabilities): return .success(capabilities)
        case .textFailed(let error): return .failure(error)
        default: throw Self.unexpected("textCapabilities")
        }
    }

    /// The warm-up stops in the worker when the calling task is cancelled.
    public func warmUpText(_ languages: [LanguageTag]) async throws(JobError) -> Result<Void, TextError> {
        let job = JobID()
        switch try await cancellable(.warmUpText(job, languages), job: job) {
        case .accepted: return .success(())
        case .textFailed(let error): return .failure(error)
        default: throw Self.unexpected("warmUpText")
        }
    }

    /// One request; a `.failed` reply is thrown.
    public func send(_ request: WorkerRequest) async throws(JobError) -> WorkerReply {
        try await send(request, on: try currentSession())
    }

    /// Ends the session (quit). No later call opens another: each throws `.cancelled`.
    public func close() {
        let session = state.withLock { state in
            defer {
                state.session = nil
                state.closed = true
            }
            return state.session
        }
        session?.channel.close()
    }

    /// Delivers one event to the job's context; an event for a job nobody waits for is dropped.
    func route(_ event: WorkerEvent) {
        guard let context = state.withLock({ $0.routes[event.job] }) else {
            Self.logger.debug("Worker event for an unknown job dropped: \(event.job, privacy: .public)")
            return
        }
        switch event {
        case .progress(_, let progress): context.progress.report(progress)
        case .spawned(_, let pid): context.spawned(pid)
        }
    }

    private func send(_ request: WorkerRequest, on session: Session) async throws(JobError) -> WorkerReply {
        let reply: WorkerReply
        do {
            reply = try await session.channel.send(request)
        } catch {
            if error == .workerCrashed { drop(session.id, closing: session.channel) }
            throw error
        }
        if case .failed(let error) = reply { throw error }
        return reply
    }

    /// A request whose job stops in the worker when the calling task is cancelled. The session is open before the
    /// cancellation handler is, so a cancel always has the request's session to go to; one that comes before the
    /// request is sent is caught by the check inside.
    private func cancellable(_ request: WorkerRequest, job: JobID) async throws(JobError) -> WorkerReply {
        if Task.isCancelled { throw .cancelled }
        let session = try currentSession()
        let result = await withTaskCancellationHandler {
            await Result { () async throws(JobError) -> WorkerReply in
                if Task.isCancelled { throw .cancelled }
                return try await send(request, on: session)
            }
        } onCancel: {
            Task { await Self.sendCancel(job, on: session.channel) }
        }
        return try result.get()
    }

    /// A dead session already cancelled its jobs, so a failed cancel is only logged.
    private static func sendCancel(_ job: JobID, on channel: any WorkerChannel) async {
        do {
            _ = try await channel.send(.cancel(job))
        } catch {
            logger.debug("Cancel not delivered: \(error.logDescription, privacy: .public)")
        }
    }

    /// Opens are serialised by their own lock, so two first calls share one session; the transport's callbacks
    /// take only `state`, never this lock.
    private func currentSession() throws(JobError) -> Session {
        let (current, closed) = state.withLock { ($0.session, $0.closed) }
        if closed { throw .cancelled }
        if let current { return current }
        let opened: Result<Session, JobError> = opening.withLock { _ in
            let (current, closed) = state.withLock { ($0.session, $0.closed) }
            if closed { return .failure(.cancelled) }
            if let current { return .success(current) }
            let id = state.withLock { state in
                state.opened += 1
                return state.opened
            }
            return Result { () throws(JobError) -> Session in
                let channel = try transport.open(
                    onEvent: { [weak self] event in self?.route(event) }, onClosed: { [weak self] in self?.drop(id) })
                let session = Session(id: id, channel: channel)
                state.withLock { $0.session = session }
                return session
            }
        }
        return try opened.get()
    }

    /// Forgets session `id` if it is still the current one; `closing` also ends its channel, so a session that broke
    /// a reply does not stay connected beside the next one.
    private func drop(_ id: Int, closing channel: (any WorkerChannel)? = nil) {
        state.withLock { state in
            if state.session?.id == id { state.session = nil }
        }
        channel?.close()
    }

    private static func unexpected(_ step: String) -> JobError {
        .internalInvariant("The worker answered \(step) with another reply.")
    }
}

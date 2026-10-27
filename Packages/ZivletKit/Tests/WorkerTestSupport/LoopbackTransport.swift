import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletRuntime
import ZivletWorkerCore

/// A worker transport inside the test process: every request, reply and event is JSON-encoded and decoded through
/// an `Envelope`, so a Codable mistake fails a unit test. It "crashes" as told: the channel closes, every call in
/// flight fails with `.workerCrashed`, and the steps its session was running are cancelled in the service (a dead
/// worker stops its work too). Each channel is its own session, as each relaunch is in the app.
public final class LoopbackTransport: WorkerTransport {
    public enum CrashRule: Sendable {
        case never
        /// The n-th request over the transport's lifetime (1-based) crashes the worker on arrival.
        case onCall(Int)
        /// Every prepare (or text job whose first file has this name) crashes the worker.
        case whenInputIs(String)
        /// Only the first such request crashes the worker.
        case onceWhenInputIs(String)
    }

    struct State {
        var opened = 0
        var calls = 0
        var attempts: [String: Int] = [:]
        var current: LoopbackChannel?
        /// Jobs whose second attempt has prepared but not yet reached verify, and the most at once.
        var retrying: Set<String> = []
        var maxRetrying = 0
    }

    let service: WorkerService
    let crash: CrashRule
    let state = Mutex(State())

    public init(service: WorkerService, crash: CrashRule = .never) {
        self.service = service
        self.crash = crash
    }

    public var openCount: Int { state.withLock(\.opened) }

    /// The most second attempts that were between prepare and verify at the same time.
    public var maxConcurrentRetries: Int { state.withLock(\.maxRetrying) }

    /// How many prepares (or text jobs led by this file) arrived for an input with this file name.
    public func attempts(for name: String) -> Int { state.withLock { $0.attempts[name] ?? 0 } }

    public func open(onEvent: @escaping @Sendable (WorkerEvent) -> Void, onClosed: @escaping @Sendable () -> Void)
        throws(JobError) -> any WorkerChannel
    {
        let channel = LoopbackChannel(transport: self, onEvent: onEvent, onClosed: onClosed)
        state.withLock { state in
            state.opened += 1
            state.current = channel
        }
        return channel
    }

    /// The worker exits while idle: the channel closes with nothing in flight.
    public func closeIdle() {
        state.withLock(\.current)?.closeFromWorker()
    }

    /// Counts the request and says whether it crashes the worker.
    func arrives(_ request: WorkerRequest) -> Bool {
        state.withLock { state in
            state.calls += 1
            let name = Self.track(request, in: &state)
            switch crash {
            case .never: return false
            case .onCall(let n): return state.calls == n
            case .whenInputIs(let bad): return name == bad
            case .onceWhenInputIs(let bad): return name == bad && state.attempts[bad] == 1
            }
        }
    }

    /// Counts prepares per input name and follows second attempts until their verify; returns the prepared name.
    private static func track(_ request: WorkerRequest, in state: inout State) -> String? {
        switch request {
        case .prepare(let job, _):
            let name = job.input.fileName
            state.attempts[name, default: 0] += 1
            if state.attempts[name] == 2 {
                state.retrying.insert(job.id.description)
                state.maxRetrying = max(state.maxRetrying, state.retrying.count)
            }
            return name
        case .recognizeText(let job):
            let name = job.inputs.first?.lastPathComponent ?? ""
            state.attempts[name, default: 0] += 1
            return name
        case .verify(let output, _):
            let folder = output.url.deletingLastPathComponent().lastPathComponent
            state.retrying = state.retrying.filter { !folder.hasSuffix($0) }
            return nil
        default: return nil
        }
    }
}

/// One session of the loopback transport.
final class LoopbackChannel: WorkerChannel {
    typealias Waiter = CheckedContinuation<Result<WorkerReply, JobError>, Never>

    struct State {
        var closed = false
        var waiting: [UUID: Waiter] = [:]
    }

    let transport: LoopbackTransport
    let onEvent: @Sendable (WorkerEvent) -> Void
    let onClosed: @Sendable () -> Void
    let state = Mutex(State())
    let session = WorkerSessionID()

    init(
        transport: LoopbackTransport, onEvent: @escaping @Sendable (WorkerEvent) -> Void,
        onClosed: @escaping @Sendable () -> Void
    ) {
        self.transport = transport
        self.onEvent = onEvent
        self.onClosed = onClosed
    }

    func send(_ request: WorkerRequest) async throws(JobError) -> WorkerReply {
        let wire: WorkerRequest
        do {
            wire = try Envelope<WorkerRequest>.decode(Envelope(request).encoded()).body
        } catch {
            throw .internalInvariant("loopback request: \(error)")
        }
        let call = UUID()
        let result = await withCheckedContinuation { (waiter: Waiter) in
            let accepted = state.withLock { state in
                guard !state.closed else { return false }
                state.waiting[call] = waiter
                return true
            }
            guard accepted else { return waiter.resume(returning: .failure(.workerCrashed)) }
            if transport.arrives(wire) { return closeFromWorker() }
            Task { await self.serve(wire, call: call) }
        }
        return try result.get()
    }

    func close() {
        state.withLock { $0.closed = true }
    }

    /// A request that reaches a closed session is never started; its call fails as a dead session's calls do.
    private func serve(_ request: WorkerRequest, call: UUID) async {
        let (closed, unserved) = state.withLock { state in
            (state.closed, state.closed ? state.waiting.removeValue(forKey: call) : nil)
        }
        if closed {
            unserved?.resume(returning: .failure(.workerCrashed))
            return
        }
        let onEvent = self.onEvent
        let reply = await transport.service.handle(request, session: session) { event in
            guard let wire = try? Envelope<WorkerEvent>.decode(Envelope(event).encoded()).body else { return }
            onEvent(wire)
        }
        let decoded = Result<WorkerReply, JobError> { () throws(JobError) -> WorkerReply in
            do {
                return try Envelope<WorkerReply>.decode(Envelope(reply).encoded()).body
            } catch {
                throw .internalInvariant("loopback reply: \(error)")
            }
        }
        let waiter = state.withLock { $0.waiting.removeValue(forKey: call) }
        waiter?.resume(returning: decoded)
    }

    /// The worker died (or exited idle): every waiting call fails, the jobs stop, the app hears the close.
    func closeFromWorker() {
        let waiting = state.withLock { state in
            state.closed = true
            defer { state.waiting = [:] }
            return Array(state.waiting.values)
        }
        waiting.forEach { $0.resume(returning: .failure(.workerCrashed)) }
        let (service, session) = (transport.service, session)
        Task { await service.endSession(session) }
        onClosed()
    }
}

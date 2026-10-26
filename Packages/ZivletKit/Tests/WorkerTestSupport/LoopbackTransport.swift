import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletRuntime
import ZivletWorkerCore

/// A worker transport inside the test process: every request, reply and event is JSON-encoded and decoded through
/// an `Envelope`, so a Codable mistake fails a unit test. It "crashes" as told: the channel closes, every call in
/// flight fails with `.workerCrashed`, and the jobs it was running are cancelled in the service (a dead worker
/// stops its work too).
public final class LoopbackTransport: WorkerTransport {
    public enum CrashRule: Sendable {
        case never
        /// The n-th request over the transport's lifetime (1-based) crashes the worker on arrival.
        case onCall(Int)
        /// Every prepare of an input with this file name crashes the worker.
        case whenInputIs(String)
    }

    struct State {
        var opened = 0
        var calls = 0
        var attempts: [String: Int] = [:]
        var current: LoopbackChannel?
    }

    let service: WorkerService
    let crash: CrashRule
    let state = Mutex(State())

    public init(service: WorkerService, crash: CrashRule = .never) {
        self.service = service
        self.crash = crash
    }

    public var openCount: Int { state.withLock(\.opened) }

    /// How many prepares arrived for an input with this file name.
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
            var name: String?
            if case .prepare(let job, _) = request {
                name = job.input.fileName
                state.attempts[job.input.fileName, default: 0] += 1
            }
            switch crash {
            case .never: return false
            case .onCall(let n): return state.calls == n
            case .whenInputIs(let bad): return name == bad
            }
        }
    }
}

/// One session of the loopback transport.
final class LoopbackChannel: WorkerChannel {
    typealias Waiter = CheckedContinuation<Result<WorkerReply, JobError>, Never>

    struct State {
        var closed = false
        var waiting: [UUID: Waiter] = [:]
        var jobs: Set<JobID> = []
    }

    let transport: LoopbackTransport
    let onEvent: @Sendable (WorkerEvent) -> Void
    let onClosed: @Sendable () -> Void
    let state = Mutex(State())

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
                if let job = Self.job(of: wire) { state.jobs.insert(job) }
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

    private func serve(_ request: WorkerRequest, call: UUID) async {
        let onEvent = self.onEvent
        let reply = await transport.service.handle(request) { event in
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
        let (waiting, jobs) = state.withLock { state in
            state.closed = true
            defer {
                state.waiting = [:]
                state.jobs = []
            }
            return (Array(state.waiting.values), state.jobs)
        }
        waiting.forEach { $0.resume(returning: .failure(.workerCrashed)) }
        let service = transport.service
        Task { for job in jobs { _ = await service.handle(.cancel(job), events: { _ in }) } }
        onClosed()
    }

    private static func job(of request: WorkerRequest) -> JobID? {
        switch request {
        case .prepare(let job, _): job.id
        case .execute(let job, _, _): job
        default: nil
        }
    }
}

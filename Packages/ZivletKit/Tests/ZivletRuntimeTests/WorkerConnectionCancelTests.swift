import EngineTestSupport
import EngineVision
import Foundation
import Synchronization
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

@Suite("A cancel reaches the worker without opening a new one, and quit stays quit (P2-01)")
struct WorkerConnectionCancelTests {
    /// The session ended (the worker crashed) while a job was still waiting for its reply; then the job is cancelled.
    /// The cancel goes to the session the job ran on, never to a new worker launched just to receive it.
    @Test func aCancelAfterTheSessionEndedLaunchesNoWorker() async throws {
        let rig = try StagingRig()
        let transport = ProbeTransport()
        let connection = WorkerConnection(transport: transport)
        let (job, plan) = try rig.plan()
        let task = Task {
            await outcome { () throws(JobError) in try await connection.execute(plan, job: job, context: .init()) }
        }
        try await transport.waitUntilWaiting(job)
        transport.endSession(1)
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
        #expect(transport.openCount == 1)
        #expect(transport.cancels == [ProbeTransport.Cancel(session: 1, job: job)])
    }

    @Test func afterCloseNoCallReopensTheWorker() async throws {
        let transport = ProbeTransport()
        let connection = WorkerConnection(transport: transport)
        _ = try await connection.ping()
        connection.close()
        await #expect(throws: JobError.cancelled) { try await connection.ping() }
        #expect(transport.openCount == 1)
    }

    @Test func aChannelDroppedForACrashIsClosed() async throws {
        let transport = ProbeTransport(crashOnPing: true)
        let connection = WorkerConnection(transport: transport)
        await #expect(throws: JobError.workerCrashed) { try await connection.ping() }
        #expect(transport.closedSessions == [1])
    }

    /// The finding's case: the job is cancelled at once, before or while its request is sent. It must stop, not run
    /// to the end.
    @Test func aCancelRightAfterTheCallStartsStopsTheJob() async throws {
        let rig = try StagingRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let service = WorkerService.scripted(engine)
        let connection = WorkerConnection(transport: LoopbackTransport(service: service))
        for _ in 0..<20 {
            let (job, plan) = try rig.plan()
            let task = Task {
                await outcome { () throws(JobError) in try await connection.execute(plan, job: job, context: .init()) }
            }
            task.cancel()
            #expect(await task.value == .failure(.cancelled))
        }
        for _ in 0..<500 where await !service.runningJobs.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await service.runningJobs.isEmpty)
    }

    @Test func cancellingTheWarmUpStopsItInTheWorker() async throws {
        let recognizer = ScriptedRecognizer(["x"], delay: .seconds(2))
        let capabilities = VisionCapabilities(languages: [.english], osBuild: "26A1")
        let service = WorkerService(
            engines: [], text: TextReader(recognizer: recognizer, capabilities: { capabilities }), onIdle: {})
        let connection = WorkerConnection(transport: LoopbackTransport(service: service))
        let task = Task { () -> Result<Void, TextError>? in try? await connection.warmUpText([.english]) }
        for _ in 0..<500 where recognizer.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        task.cancel()
        let result = await task.value
        #expect(result.map { if case .failure(.cancelled) = $0 { true } else { false } } ?? true)
        #expect(recognizer.calls == 1)
    }
}

/// A transport whose execute steps wait until a cancel for their job arrives on any session, and which records each
/// session it opens, closes or receives a cancel on. `endSession` runs the session's `onClosed`, as XPC does when
/// the worker dies.
final class ProbeTransport: WorkerTransport {
    struct Cancel: Equatable {
        let session: Int
        let job: JobID
    }

    struct State {
        var opened = 0
        var closers: [@Sendable () -> Void] = []
        var waiting: [JobID: CheckedContinuation<WorkerReply, Never>] = [:]
        var cancelledEarly: Set<JobID> = []
        var cancels: [Cancel] = []
        var closed: [Int] = []
    }

    let crashOnPing: Bool
    let state = Mutex(State())

    init(crashOnPing: Bool = false) { self.crashOnPing = crashOnPing }

    var openCount: Int { state.withLock(\.opened) }
    var cancels: [Cancel] { state.withLock(\.cancels) }
    var closedSessions: [Int] { state.withLock(\.closed) }

    func open(onEvent: @escaping @Sendable (WorkerEvent) -> Void, onClosed: @escaping @Sendable () -> Void)
        throws(JobError) -> any WorkerChannel
    {
        let id = state.withLock { state in
            state.opened += 1
            state.closers.append(onClosed)
            return state.opened
        }
        return ProbeChannel(session: id, transport: self)
    }

    func endSession(_ session: Int) {
        state.withLock { $0.closers[session - 1] }()
    }

    func waitUntilWaiting(_ job: JobID) async throws {
        for _ in 0..<500 where state.withLock({ $0.waiting[job] == nil }) { try await Task.sleep(for: .milliseconds(2)) }
        try #require(state.withLock { $0.waiting[job] != nil })
    }

    func wait(_ job: JobID) async -> WorkerReply {
        await withCheckedContinuation { continuation in
            let now = state.withLock { state in
                if state.cancelledEarly.remove(job) != nil { return true }
                state.waiting[job] = continuation
                return false
            }
            if now { continuation.resume(returning: .failed(.cancelled)) }
        }
    }

    func cancel(_ job: JobID, on session: Int) {
        let waiter = state.withLock { state in
            state.cancels.append(Cancel(session: session, job: job))
            guard let waiter = state.waiting.removeValue(forKey: job) else {
                state.cancelledEarly.insert(job)
                return CheckedContinuation<WorkerReply, Never>?.none
            }
            return waiter
        }
        waiter?.resume(returning: .failed(.cancelled))
    }

    func closed(_ session: Int) { state.withLock { $0.closed.append(session) } }
}

struct ProbeChannel: WorkerChannel {
    let session: Int
    let transport: ProbeTransport

    func send(_ request: WorkerRequest) async throws(JobError) -> WorkerReply {
        switch request {
        case .ping:
            if transport.crashOnPing { throw .workerCrashed }
            return .pong(pid: 1, osBuild: "26A1")
        case .execute(let job, _, _): return await transport.wait(job)
        case .cancel(let job):
            transport.cancel(job, on: session)
            return .accepted
        default: return .accepted
        }
    }

    func close() { transport.closed(session) }
}

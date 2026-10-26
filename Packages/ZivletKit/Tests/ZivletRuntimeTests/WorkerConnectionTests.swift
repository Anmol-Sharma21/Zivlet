import Darwin
import EngineTestSupport
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

/// Real staging folders for requests that pass the worker's validator.
struct StagingRig {
    let dir: TempDir

    init() throws { dir = try TempDir(prefix: "zivlet-connection") }

    func plan() throws -> (JobID, ExecutionPlan) {
        let job = JobID()
        let staged = try dir.folder(".zivlet-\(job)").appending(path: "staged.jpg")
        try Data().write(to: staged)
        return (job, try ScriptedEngine.plan(staged: staged))
    }
}

extension WorkerService {
    static func scripted(_ engine: ScriptedEngine = ScriptedEngine()) -> WorkerService {
        WorkerService(engines: [engine], onIdle: {})
    }
}

/// What one call ended with.
func outcome(_ call: @Sendable () async throws(JobError) -> StagedOutput) async -> Result<StagedOutput, JobError> {
    do {
        return .success(try await call())
    } catch {
        return .failure(error)
    }
}

@Suite("The worker connection notices a crash and reopens (P2-01, D-M6-2)")
struct WorkerConnectionTests {
    @Test func aPingCrossesTheLoopback() async throws {
        let transport = LoopbackTransport(service: .scripted())
        let connection = WorkerConnection(transport: transport)
        let pong = try await connection.ping()
        #expect(pong.pid == getpid() && pong.osBuild == WorkerService.osBuild)
        #expect(transport.openCount == 1)
    }

    @Test func aCrashFailsEveryCallInFlightAndTheNextCallReopens() async throws {
        let rig = try StagingRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let transport = LoopbackTransport(service: .scripted(engine), crash: .onCall(3))
        let connection = WorkerConnection(transport: transport)
        let (j1, p1) = try rig.plan()
        let (j2, p2) = try rig.plan()
        let (j3, p3) = try rig.plan()
        async let a = outcome { () throws(JobError) in try await connection.execute(p1, job: j1, context: .init()) }
        async let b = outcome { () throws(JobError) in try await connection.execute(p2, job: j2, context: .init()) }
        while engine.executeCount < 2 { try await Task.sleep(for: .milliseconds(2)) }
        async let c = outcome { () throws(JobError) in try await connection.execute(p3, job: j3, context: .init()) }
        let results = await [a, b, c]
        #expect(results.allSatisfy { $0 == .failure(.workerCrashed) })
        #expect(try await connection.ping().pid > 0)
        let opened = transport.openCount
        #expect(opened == 2, "opened \(opened)")
    }

    @Test func concurrentFirstCallsShareOneSession() async throws {
        let transport = LoopbackTransport(service: .scripted())
        let connection = WorkerConnection(transport: transport)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await connection.ping() } }
            try await group.waitForAll()
        }
        #expect(transport.openCount == 1)
    }

    @Test func anIdleCloseFailsNothingAndTheNextCallReopens() async throws {
        let transport = LoopbackTransport(service: .scripted())
        let connection = WorkerConnection(transport: transport)
        _ = try await connection.ping()
        transport.closeIdle()
        _ = try await connection.ping()
        #expect(transport.openCount == 2)
    }

    @Test func eventsReachTheJobsContextAndUnknownJobsAreDropped() async throws {
        let rig = try StagingRig()
        let transport = LoopbackTransport(service: .scripted(ScriptedEngine(execution: .reportProgress)))
        let connection = WorkerConnection(transport: transport)
        let (job, plan) = try rig.plan()
        let seen = ProgressLog()
        let context = ExecutionContext(progress: ProgressSink(interval: .zero) { seen.append($0.fraction) })
        let output = try await connection.execute(plan, job: job, context: context)
        #expect(output.byteCount == 3)
        #expect(seen.values == [0.5, 1])
        connection.route(.progress(JobID(), JobProgress(fraction: 0.3)))  // nobody waits for it: dropped
        #expect(seen.values == [0.5, 1])
    }

    @Test func aSpawnedChildReachesTheContext() async throws {
        let rig = try StagingRig()
        let transport = LoopbackTransport(service: .scripted(ScriptedEngine(execution: .spawn(4321))))
        let connection = WorkerConnection(transport: transport)
        let (job, plan) = try rig.plan()
        let pids = ProgressLog()
        _ = try await connection.execute(
            plan, job: job, context: ExecutionContext(spawned: { pids.append(Double($0)) }))
        #expect(pids.values == [4321])
    }

    @Test func aFailedReplyIsThrown() async throws {
        let rig = try StagingRig()
        let transport = LoopbackTransport(service: .scripted(ScriptedEngine(execution: .fail(.writeFailed("x")))))
        let connection = WorkerConnection(transport: transport)
        let (job, plan) = try rig.plan()
        let result = await outcome { () throws(JobError) in
            try await connection.execute(plan, job: job, context: .init())
        }
        #expect(result == .failure(.writeFailed("x")))
    }

    @Test func aTransportThatCannotOpenFailsTheCall() async {
        let connection = WorkerConnection(transport: UnopenableTransport())
        await #expect(throws: JobError.engineMissing(.worker)) { try await connection.ping() }
    }

    @Test func crashCopyNamesTheConverterAndTheFile() {
        #expect(JobErrorCopy.copy(for: .workerCrashed).message == "The converter stopped unexpectedly.")
        #expect(JobErrorCopy.copy(for: .engineCrashedOnInput).message == "This file made the engine crash.")
        #expect(JobError.workerCrashed.logDescription == "workerCrashed")
        #expect(JobError.engineCrashedOnInput.logDescription == "engineCrashedOnInput")
    }
}

/// Values in arrival order.
final class ProgressLog: Sendable {
    private let log = Mutex<[Double?]>([])
    var values: [Double?] { log.withLock { $0 } }
    func append(_ value: Double?) { log.withLock { $0.append(value) } }
}

struct UnopenableTransport: WorkerTransport {
    func open(onEvent: @escaping @Sendable (WorkerEvent) -> Void, onClosed: @escaping @Sendable () -> Void)
        throws(JobError) -> any WorkerChannel
    {
        throw .engineMissing(.worker)
    }
}

import Darwin
import EngineTestSupport
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

@Suite("The app's XPC transport against a worker listener in this process (P2-01, R7)")
struct XPCSessionFactoryTests {
    @Test func aPingAndAJobCrossRealXPC() async throws {
        let rig = try StagingRig()
        let listener = WorkerXPCHost.anonymous(service: .scripted(ScriptedEngine(execution: .reportProgress)))
        defer { listener.cancel() }
        let connection = WorkerConnection(transport: XPCSessionFactory(endpoint: listener.endpoint))
        defer { connection.close() }
        #expect(try await connection.ping().pid == getpid())
        let (job, plan) = try rig.plan()
        let seen = ProgressLog()
        let context = ExecutionContext(progress: ProgressSink(interval: .zero) { seen.append($0.fraction) })
        let output = try await connection.execute(plan, job: job, context: context)
        #expect(output.byteCount == 3 && seen.values == [0.5, 1])
    }

    @Test func aFailedReplyAndACancelCrossRealXPC() async throws {
        let rig = try StagingRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let listener = WorkerXPCHost.anonymous(service: .scripted(engine))
        defer { listener.cancel() }
        let connection = WorkerConnection(transport: XPCSessionFactory(endpoint: listener.endpoint))
        defer { connection.close() }
        let (job, plan) = try rig.plan()
        let task = Task {
            await outcome { () throws(JobError) in try await connection.execute(plan, job: job, context: .init()) }
        }
        await engine.reachedExecute.wait()
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
    }

    @Test func aListenerThatGoesAwayFailsTheCallInFlight() async throws {
        let rig = try StagingRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let listener = WorkerXPCHost.anonymous(service: .scripted(engine))
        let connection = WorkerConnection(transport: XPCSessionFactory(endpoint: listener.endpoint))
        let (job, plan) = try rig.plan()
        async let call = outcome { () throws(JobError) in try await connection.execute(plan, job: job, context: .init())
        }
        await engine.reachedExecute.wait()
        connection.close()
        #expect(await call == .failure(.workerCrashed))
        listener.cancel()
    }
}

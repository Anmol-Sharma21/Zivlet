import EngineTestSupport
import Foundation
import Synchronization
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

/// A worker engine whose first run of `slow.png` waits in the worker until it is released (or its session ends).
struct ParkingEngine: Engine {
    final class Parking: Sendable {
        let reached = Signal()
        let release = Signal()
        let parked = Mutex(false)
    }

    let id = EngineID.image
    let parking: Parking

    func handles(_ pair: ConversionPair) -> Bool { pair.source == .png }
    func availability(of pair: ConversionPair) async -> RouteAvailability { .available }

    func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        do {
            return try ExecutionPlan(
                engine: id, stages: [.ffmpeg(FFmpegStage(argv: [request.input.fileName], expectedDurationMicros: nil))],
                stageWeights: [1], lanes: [.cpu], outputFormat: request.target, stagedFile: workspace.stagedFile)
        } catch {
            throw .internalInvariant("parking plan")
        }
    }

    func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        guard case .ffmpeg(let stage) = plan.stages.first else { throw .internalInvariant("parking stage") }
        let parks =
            stage.argv == ["slow.png"]
            && parking.parked.withLock { parked in
                defer { parked = true }
                return !parked
            }
        if parks {
            parking.reached.fire()
            while !parking.release.hasFired {
                if Task.isCancelled { throw .cancelled }
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
        do {
            try Data("out".utf8).write(to: plan.stagedFile)
        } catch {
            throw .writeFailed("parking")
        }
        return StagedOutput(format: plan.outputFormat, url: plan.stagedFile, byteCount: 3)
    }

    func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {}
}

/// A crash retry runs alone in the worker (review of M7, D-M7-66): one file's stuck qpdf call stops the whole shared
/// worker, so a retry beside another file's first attempt could be blamed for that file's crash.
@Suite("A retry has the worker to itself")
struct WorkerIsolationRetryTests {
    /// Until `condition` holds, for at most about ten seconds; false when it never did.
    static func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<5_000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }

    @Test func anotherFilesCrashBesideARetryDoesNotBlameTheRetriedFile() async throws {
        let box = try Sandbox()
        let parking = ParkingEngine.Parking()
        let service = WorkerService(engines: [ParkingEngine(parking: parking)], onIdle: {})
        let transport = LoopbackTransport(
            service: service, crash: .any([.onceWhenInputIs("slow.png"), .whenInputIs("bad.png")]))
        let connection = WorkerConnection(transport: transport)
        let capability = try #require(try await connection.capabilities().engine(.image))
        let scheduler = JobScheduler(
            engines: [RemoteEngine(capability: capability, connection: connection)],
            lanes: .standard(performanceCores: 4), records: nil, processes: SystemProcesses(), clock: { .zero })
        try box.file("slow.png")
        try box.file("bad.png")
        let slow = try box.request("slow.png", .png, to: .jpg)
        let bad = try box.request("bad.png", .png, to: .jpg)
        let first = BatchID()
        let second = BatchID()
        let collector = Task { await scheduler.collect(untilAll: [first, second]) }

        await scheduler.submit([slow], as: first)
        await parking.reached.wait()  // slow.png crashed once and its retry now runs in the worker
        await scheduler.submit([bad], as: second)
        let gated = await Self.eventually { await connection.isolation.waiting > 0 }
        let arrivedBeside = transport.attempts(for: "bad.png")
        parking.release.fire()
        let events = await collector.value

        #expect(gated, "bad.png waits for the retry to end")
        #expect(arrivedBeside == 0, "nothing else reached the worker beside the retry")
        #expect(events.states(of: slow.id).last?.published != nil, "\(events.states(of: slow.id))")
        #expect(events.states(of: bad.id).last == .failed(.engineCrashedOnInput))
        #expect(transport.attempts(for: "slow.png") == 2 && transport.attempts(for: "bad.png") == 2)
    }
}

extension JobScheduler {
    /// Every event until each of `batches` has finished.
    func collect(untilAll batches: Set<BatchID>) async -> [JobEvent] {
        var seen: [JobEvent] = []
        var open = batches
        for await event in events {
            seen.append(event)
            if case .finished(let batch) = event { open.remove(batch) }
            if open.isEmpty { break }
        }
        return seen
    }
}

import EngineTestSupport
import Foundation
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

/// A scheduler whose one engine runs in a loopback worker that crashes as told.
struct RetryRig {
    let box: Sandbox
    let transport: LoopbackTransport
    let scheduler: JobScheduler

    init(crash: LoopbackTransport.CrashRule) async throws {
        box = try Sandbox()
        let service = WorkerService(engines: [ScriptedEngine()], onIdle: {})
        transport = LoopbackTransport(service: service, crash: crash)
        let connection = WorkerConnection(transport: transport)
        let capability = try #require(try await connection.capabilities().engine(.image))
        scheduler = JobScheduler(
            engines: [RemoteEngine(capability: capability, connection: connection)],
            lanes: .standard(performanceCores: 4), records: nil, processes: SystemProcesses(), clock: { .zero })
    }

    /// Runs one batch of PNG → JPEG jobs and returns each file's states.
    func run(_ names: [String]) async throws -> [String: [JobState]] {
        let requests = try names.map { name in
            try box.file(name)
            return try box.request(name, .png, to: .jpg)
        }
        let batch = await scheduler.submit(requests)
        let events = await scheduler.collect(until: batch)
        await scheduler.waitUntilIdle()
        var states: [String: [JobState]] = [:]
        for request in requests { states[request.input.fileName] = events.states(of: request.id) }
        return states
    }
}

@Suite("One serial retry after a worker crash, then the file is named (P2-01, plan 18c C6)")
struct WorkerRetryTests {
    @Test func aCrashIsRetriedOnceAndEveryJobOfTheBatchSucceeds() async throws {
        let rig = try await RetryRig(crash: .onceWhenInputIs("c.png"))
        let states = try await rig.run(["a.png", "b.png", "c.png", "d.png", "e.png"])
        for (name, history) in states {
            #expect(history.last?.published != nil, "\(name): \(history)")
        }
        #expect(rig.transport.attempts(for: "c.png") == 2)
        #expect(states["c.png"]?.contains(.retrying) == true)
        #expect(rig.transport.maxConcurrentRetries == 1)
        #expect(!rig.box.listing.contains { $0.hasPrefix(".zivlet-") })
    }

    @Test func aFileThatCrashesTwiceFailsAloneAndTheBatchGoesOn() async throws {
        let rig = try await RetryRig(crash: .whenInputIs("bad.png"))
        let states = try await rig.run(["a.png", "bad.png", "c.png"])
        #expect(states["bad.png"]?.last == .failed(.engineCrashedOnInput))
        #expect(states["a.png"]?.last?.published != nil && states["c.png"]?.last?.published != nil)
        #expect(rig.transport.attempts(for: "bad.png") == 2)
        #expect(rig.box.listing.sorted() == ["a.jpg", "a.png", "bad.png", "c.jpg", "c.png"])
    }

    @Test func retriesWaitForOneAnother() {
        #expect(LaneGates(.standard(performanceCores: 8)).retry.width == 1)
    }

    @Test func aRetryingJobSaysTheConverterIsTryingAgain() throws {
        let box = try Sandbox()
        let request = try box.request("photo.png", .png, to: .jpg)
        let plan = RequestPlan(requests: [request], rejections: [])
        let batch = BatchID()
        let snapshot = BatchSnapshot(batch: batch, target: .jpg, plan: plan)
            .applying(.changed(batch, request.id, .retrying))
        let shown = BatchPresentation.make(snapshot)
        #expect(shown.phase == .working)
        #expect(shown.subtitle == "The converter stopped unexpectedly. Trying again…")
    }
}

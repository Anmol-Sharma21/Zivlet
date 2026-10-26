import Darwin
import EngineTestSupport
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@testable import ZivletWorkerCore

@Suite("The worker's logic without XPC (P2-01, plan 18c C3)")
struct WorkerServiceTests {
    @Test func prepareReturnsTheEnginesPlan() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine()])
        let (request, workspace) = try rig.job()
        let reply = await service.handle(.prepare(request, workspace), events: { _ in })
        #expect(reply == .planned(try ScriptedEngine.plan(staged: workspace.stagedFile)))
    }

    @Test func executeStagesTheOutputAndReportsProgressInOrder() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine(execution: .reportProgress)])
        let (job, request) = try rig.executeRequest()
        let log = EventLog()
        let reply = await service.handle(request, events: log.sink)
        guard case .staged(let output) = reply else {
            Issue.record("not staged: \(reply)")
            return
        }
        #expect(output.byteCount == 3)
        #expect(log.all == [.progress(job, JobProgress(fraction: 0.5)), .progress(job, JobProgress(fraction: 1))])
    }

    @Test func aSpawnedChildIsReportedAsAnEvent() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine(execution: .spawn(777))])
        let (job, request) = try rig.executeRequest()
        let log = EventLog()
        _ = await service.handle(request, events: log.sink)
        #expect(log.all == [.spawned(job, 777)])
    }

    @Test func cancelStopsARunningExecuteQuickly() async throws {
        let rig = try WorkerRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let service = WorkerRig.service([engine])
        let (job, request) = try rig.executeRequest()
        async let reply = service.handle(request, events: { _ in })
        await engine.reachedExecute.wait()
        let started = ContinuousClock.now
        #expect(await service.handle(.cancel(job), events: { _ in }) == .accepted)
        #expect(await reply == .failed(.cancelled))
        #expect(ContinuousClock.now - started < .milliseconds(100))
    }

    @Test func twoJobsRunIndependently() async throws {
        let rig = try WorkerRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let service = WorkerRig.service([engine])
        let (first, firstRequest) = try rig.executeRequest()
        let (second, secondRequest) = try rig.executeRequest()
        async let a = service.handle(firstRequest, events: { _ in })
        async let b = service.handle(secondRequest, events: { _ in })
        while engine.executeCount < 2 { try await Task.sleep(for: .milliseconds(2)) }
        _ = await service.handle(.cancel(first), events: { _ in })
        #expect(await a == .failed(.cancelled))
        #expect(await service.runningJobs == [second])
        _ = await service.handle(.cancel(second), events: { _ in })
        #expect(await b == .failed(.cancelled))
    }

    @Test func aCancelForAnUnknownJobIsANoOp() async {
        let service = WorkerRig.service([ScriptedEngine()])
        #expect(await service.handle(.cancel(JobID()), events: { _ in }) == .accepted)
    }

    @Test func anEngineTheWorkerDoesNotHostIsMissing() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine()])
        let (_, request) = try rig.executeRequest(engine: .media)
        #expect(await service.handle(request, events: { _ in }) == .failed(.engineMissing(.media)))
    }

    @Test func anInvalidRequestNeverReachesTheEngine() async throws {
        let rig = try WorkerRig()
        let engine = ScriptedEngine()
        let service = WorkerRig.service([engine])
        let (request, _) = try rig.job()
        let outside = JobWorkspace(job: request.id, stagedFile: rig.dir.url.appending(path: "staged.jpg"))
        #expect(await service.handle(.prepare(request, outside), events: { _ in }) == .failed(.invalidDestination))
        #expect(engine.executeCount == 0)
    }

    @Test func engineErrorsComeBackAsFailures() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine(execution: .fail(.writeFailed("encoder")))])
        let (_, request) = try rig.executeRequest()
        #expect(await service.handle(request, events: { _ in }) == .failed(.writeFailed("encoder")))
    }

    @Test func verifyChecksTheStagedFile() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine()])
        let (_, workspace) = try rig.job()
        let plan = try ScriptedEngine.plan(staged: workspace.stagedFile)
        let good = StagedOutput(format: .jpg, url: workspace.stagedFile, byteCount: 3)
        let empty = StagedOutput(format: .jpg, url: workspace.stagedFile, byteCount: 0)
        #expect(await service.handle(.verify(good, plan), events: { _ in }) == .verified)
        #expect(await service.handle(.verify(empty, plan), events: { _ in }) == .failed(.verificationFailed("empty")))
    }

    @Test func pingAnswersWithThisProcessAndTheOSBuild() async {
        let service = WorkerRig.service([ScriptedEngine()])
        #expect(await service.handle(.ping, events: { _ in }) == .pong(pid: getpid(), osBuild: WorkerService.osBuild))
    }

    @Test func capabilitiesListEveryCatalogRouteAnEngineHandles() async throws {
        let service = WorkerRig.service([ScriptedEngine()])
        guard case .capabilities(let capabilities) = await service.handle(.capabilities, events: { _ in }) else {
            Issue.record("no capabilities")
            return
        }
        let image = try #require(capabilities.engine(.image))
        let pngToJPEG = ConversionPair(source: .png, target: .jpg)
        #expect(image.handles(pngToJPEG) && image.availability(of: pngToJPEG) == .available)
        #expect(image.availability(of: ConversionPair(source: .png, target: .webp)) == .unavailable(["libwebp"]))
        #expect(!image.handles(ConversionPair(source: .jpg, target: .png)))
        #expect(image.routes.allSatisfy { ConversionCatalog.standard.pairs.contains($0.pair) })
    }

    #if DEBUG
        @Test func theSmokeRequestsReachTheirHooks() async {
            let killed = IdleCounter()
            let sleeper = ManualSleeper()
            let service = WorkerService(
                engines: [ScriptedEngine()], idleAfter: .seconds(60), sleep: sleeper.sleep, onIdle: {},
                onSelfKill: { _ in killed.fire() })
            #expect(await service.handle(.selfKillForTesting(afterMilliseconds: 0), events: { _ in }) == .accepted)
            #expect(killed.fired == 1)
            #expect(await service.handle(.setIdleForTesting(seconds: 5), events: { _ in }) == .accepted)
            await sleeper.waitForRequests(3)
            #expect(sleeper.requested.last == .seconds(5))
        }
    #endif
}

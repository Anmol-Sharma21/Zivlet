import EngineTestSupport
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@testable import ZivletWorkerCore

/// A retry after a broken session reuses its job id on a new session to the same worker, so the old session's end and
/// its cancels must not reach it (G-M6-21).
@Suite("Steps belong to the session that sent them (P2-01, G-M6-21)")
struct WorkerSessionTests {
    @Test func endingASessionStopsOnlyItsOwnSteps() async throws {
        let rig = try WorkerRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let service = WorkerRig.service([engine])
        let (job, request) = try rig.executeRequest()
        let (old, new) = (WorkerSessionID(), WorkerSessionID())
        let first = Task { await service.handle(request, session: old, events: { _ in }) }
        for _ in 0..<500 where engine.executeCount < 1 { try await Task.sleep(for: .milliseconds(2)) }
        let retry = Task { await service.handle(request, session: new, events: { _ in }) }
        for _ in 0..<500 where engine.executeCount < 2 { try await Task.sleep(for: .milliseconds(2)) }
        try #require(engine.executeCount == 2)
        await service.endSession(old)
        #expect(await first.value == .failed(.cancelled))
        #expect(await service.runningJobs == [job])
        _ = await service.handle(.cancel(job), session: new, events: { _ in })
        #expect(await retry.value == .failed(.cancelled))
    }

    @Test func aCancelReachesOnlyTheJobsOfItsOwnSession() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine()])
        let (job, request) = try rig.executeRequest()
        _ = await service.handle(.cancel(job), session: WorkerSessionID(), events: { _ in })
        guard case .staged = await service.handle(request, session: WorkerSessionID(), events: { _ in }) else {
            Issue.record("another session's cancel stopped the job")
            return
        }
    }

    @Test func anEndedSessionForgetsTheCancelsItSentEarly() async throws {
        let rig = try WorkerRig()
        let service = WorkerRig.service([ScriptedEngine()])
        let (job, request) = try rig.executeRequest()
        let session = WorkerSessionID()
        _ = await service.handle(.cancel(job), session: session, events: { _ in })
        await service.endSession(session)
        guard case .staged = await service.handle(request, session: session, events: { _ in }) else {
            Issue.record("a cancel outlived its session")
            return
        }
    }
}

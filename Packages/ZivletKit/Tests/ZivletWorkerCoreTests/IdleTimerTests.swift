import EngineTestSupport
import Foundation
import Testing
import ZivletCore
import ZivletIPC

@testable import ZivletWorkerCore

@Suite("The worker exits on its own when idle (D-M6-10)")
struct IdleTimerTests {
    @Test func anArmedTimerFiresOnceAfterItsInterval() async {
        let sleeper = ManualSleeper()
        let idle = IdleCounter()
        let timer = IdleTimer(after: .seconds(60), sleep: sleeper.sleep, onIdle: { idle.fire() })
        timer.arm()
        await sleeper.waitForRequests(1)
        #expect(sleeper.requested == [.seconds(60)])
        sleeper.releaseAll()
        await idle.waitUntil(fired: 1)
        #expect(idle.fired == 1)
    }

    @Test func aDisarmedOrReArmedTimerDoesNotFireForTheOldSleep() async {
        let sleeper = ManualSleeper()
        let idle = IdleCounter()
        let timer = IdleTimer(after: .seconds(60), sleep: sleeper.sleep, onIdle: { idle.fire() })
        timer.arm()
        await sleeper.waitForRequests(1)
        timer.disarm()
        sleeper.releaseAll()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(idle.fired == 0)
        timer.arm()
        timer.arm()
        await sleeper.waitForRequests(3)
        sleeper.releaseAll()
        await idle.waitUntil(fired: 1)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(idle.fired == 1)
    }

    @Test func theServiceIsNotIdleWhileAJobRunsAndIsSixtySecondsAfterTheLast() async throws {
        let rig = try WorkerRig()
        let sleeper = ManualSleeper()
        let idle = IdleCounter()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let service = WorkerRig.service([engine], sleeper: sleeper, idle: idle)
        let (job, request) = try rig.executeRequest()
        async let reply = service.handle(request, events: { _ in })
        await engine.reachedExecute.wait()
        sleeper.releaseAll()  // the launch-time arm, disarmed by the request
        try await Task.sleep(for: .milliseconds(20))
        #expect(idle.fired == 0)
        _ = await service.handle(.cancel(job), events: { _ in })
        _ = await reply
        await sleeper.waitForRequests(2)
        #expect(sleeper.requested.last == .seconds(60))
        sleeper.releaseAll()
        await idle.waitUntil(fired: 1)
        #expect(idle.fired == 1)
    }
}

extension IdleCounter {
    func waitUntil(fired count: Int) async {
        for _ in 0..<500 where fired < count { try? await Task.sleep(for: .milliseconds(2)) }
    }
}

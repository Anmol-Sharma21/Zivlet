import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

@Suite("Lane limits under memory pressure and Low Power (P1-12, 03a §4.2)")
struct SystemLoadTests {
    static let base = LaneWidths.standard(performanceCores: 8)

    @Test func normalLoadKeepsTheTable() {
        #expect(LaneLimits(base: Self.base, load: SystemLoad()).limit(.cpu) == 8)
        #expect(LaneLimits(base: Self.base, load: SystemLoad()).limit(.remux) == 4)
    }

    @Test func aMemoryWarningHalvesEveryLaneButNeverBelowOne() {
        let limits = LaneLimits(base: Self.base, load: SystemLoad(memory: .warning))
        #expect(limits.limit(.cpu) == 4 && limits.limit(.remux) == 2 && limits.limit(.swVideo) == 1)
    }

    @Test func criticalMemoryPausesAdmissionOnEveryLane() {
        let limits = LaneLimits(base: Self.base, load: SystemLoad(memory: .critical, lowPower: true))
        #expect(Lane.allCases.allSatisfy { limits.limit($0) == 0 })
    }

    @Test func lowPowerHalvesOnlyTheCPULaneAndStacksWithAWarning() {
        let low = LaneLimits(base: Self.base, load: SystemLoad(lowPower: true))
        #expect(low.limit(.cpu) == 4 && low.limit(.audio) == 8)
        let both = LaneLimits(base: Self.base, load: SystemLoad(memory: .warning, lowPower: true))
        #expect(both.limit(.cpu) == 2 && both.limit(.audio) == 4)
        let tiny = LaneLimits(base: .standard(performanceCores: 1), load: SystemLoad(memory: .warning, lowPower: true))
        #expect(tiny.limit(.cpu) == 1)
    }

    @Test func aZeroLimitHoldsNewPermitsUntilItIsRaised() async throws {
        let semaphore = AsyncSemaphore(width: 2)
        await semaphore.setLimit(0)
        let waiter = Task { try await semaphore.acquire() }
        while await semaphore.waiting == 0 { await Task.yield() }
        #expect(await semaphore.free == 0)
        await semaphore.setLimit(2)
        try await waiter.value
        #expect(await semaphore.free == 1)
        #expect(await semaphore.waiting == 0)
    }

    @Test func loweringTheLimitNeverPreemptsAndReleasesRefillOnlyToTheNewLimit() async throws {
        let semaphore = AsyncSemaphore(width: 3)
        for _ in 0..<3 { try await semaphore.acquire() }
        await semaphore.setLimit(1)
        let waiter = Task { try await semaphore.acquire() }
        while await semaphore.waiting == 0 { await Task.yield() }
        await semaphore.release()
        await semaphore.release()
        #expect(await semaphore.waiting == 1)
        await semaphore.release()
        try await waiter.value
        #expect(await semaphore.free == 0)
        await semaphore.release()
        #expect(await semaphore.free == 1)
    }

    @Test func theLiveMonitorStartsWithTheCurrentPowerState() async {
        let monitor = SystemLoadMonitor()
        var iterator = monitor.loads.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == SystemLoad(memory: .normal, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
    }

    @Test func aServiceFedByTheLiveMonitorStillConverts() async throws {
        let box = try Sandbox()
        let scheduler = JobScheduler(engines: [FakeEngine()], lanes: .standard(performanceCores: 2), records: nil)
        let service = ConversionService(
            scheduler: scheduler, factory: JobRequestFactory(fallbackFolder: box.dir), loadMonitor: SystemLoadMonitor())
        let batch = await service.convert([try box.file("a.heic")], to: .jpg)
        let last = try #require(await service.snapshots(until: batch).last)
        #expect(last.outputs.map(\.url.lastPathComponent) == ["a.jpg"])
    }

    @Test func theSchedulerHoldsJobsWhileMemoryIsCriticalAndResumesThem() async throws {
        let box = try Sandbox()
        let scheduler = JobScheduler(
            engines: [FakeEngine()], lanes: .standard(performanceCores: 2), records: nil, processes: SystemProcesses(),
            freeSpace: FixedFreeSpace(bytes: nil), clock: { .zero })
        await scheduler.apply(SystemLoad(memory: .critical))
        let request = try box.request("a.heic", .heic, to: .jpg)
        let batch = await scheduler.submit([request])
        try await Task.sleep(for: .milliseconds(100))
        #expect(box.listing.allSatisfy { $0.hasPrefix(".zivlet-") })
        await scheduler.apply(SystemLoad())
        let states = await scheduler.collect(until: batch).states(of: request.id)
        #expect(states.last?.published?.url.lastPathComponent == "a.jpg")
    }
}

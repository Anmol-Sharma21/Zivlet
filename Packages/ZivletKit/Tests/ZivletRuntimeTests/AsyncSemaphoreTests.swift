import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// Tracks how many bodies run at once.
final class ConcurrencyMeter: Sendable {
    private let state = Mutex((current: 0, peak: 0))

    func enter() {
        state.withLock {
            $0.current += 1
            $0.peak = max($0.peak, $0.current)
        }
    }
    func leave() { state.withLock { $0.current -= 1 } }
    var peak: Int { state.withLock { $0.peak } }
}

@Suite("AsyncSemaphore and lane widths (P1-12, 03a §4.2)")
struct AsyncSemaphoreTests {
    @Test func aHundredWaitersNeverExceedTheWidth() async throws {
        let semaphore = AsyncSemaphore(width: 3)
        let meter = ConcurrencyMeter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try await semaphore.withPermit { () async throws(JobError) in
                        meter.enter()
                        try? await Task.sleep(for: .milliseconds(1))
                        meter.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(meter.peak == 3)
        #expect(await semaphore.free == 3)
    }

    @Test func aCancelledWaiterThrowsAndLeaksNoPermit() async throws {
        let semaphore = AsyncSemaphore(width: 1)
        try await semaphore.acquire()
        let waiter = Task { try await semaphore.acquire() }
        while await semaphore.waiting == 0 { await Task.yield() }
        waiter.cancel()
        await #expect(throws: JobError.cancelled) { try await waiter.value }
        #expect(await semaphore.waiting == 0)
        await semaphore.release()
        #expect(await semaphore.free == 1)
    }

    @Test func anAlreadyCancelledTaskDoesNotTakeAPermit() async {
        let semaphore = AsyncSemaphore(width: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await semaphore.acquire()
        }
        await #expect(throws: JobError.cancelled) { try await task.value }
        #expect(await semaphore.free == 1)
    }

    @Test func waitersAreServedInArrivalOrder() async throws {
        let semaphore = AsyncSemaphore(width: 1)
        try await semaphore.acquire()
        let order = Mutex<[Int]>([])
        var tasks: [Task<Void, any Error>] = []
        for index in 0..<5 {
            tasks.append(
                Task {
                    try await semaphore.acquire()
                    order.withLock { $0.append(index) }
                    await semaphore.release()
                })
            while await semaphore.waiting < index + 1 { await Task.yield() }
        }
        await semaphore.release()
        for task in tasks { try await task.value }
        #expect(order.withLock { $0 } == [0, 1, 2, 3, 4])
    }

    @Test func aFailingBodyStillReturnsThePermit() async {
        let semaphore = AsyncSemaphore(width: 1)
        await #expect(throws: JobError.diskFull) {
            try await semaphore.withPermit { () async throws(JobError) in throw .diskFull }
        }
        #expect(await semaphore.free == 1)
    }

    @Test func standardWidthsFollowTheTable() {
        let widths = LaneWidths.standard(performanceCores: 8)
        #expect(widths.width(.cpu) == 8 && widths.width(.audio) == 8 && widths.width(.remux) == 4)
        #expect(widths.width(.hwVideo) == 2 && widths.width(.swVideo) == 1 && widths.width(.js) == 2)
        #expect(widths.halved().width(.cpu) == 4 && widths.halved().width(.swVideo) == 1)
        #expect(LaneWidths([:]).width(.cpu) == 1 && LaneWidths([.cpu: 0]).width(.cpu) == 1)
        #expect(LaneWidths.performanceCores() >= 1)
        #expect(AsyncSemaphore(width: 0).width == 1)
    }

    @Test func gatesHoldOneSemaphorePerLane() {
        let gates = LaneGates(LaneWidths.standard(performanceCores: 6))
        #expect(gates.semaphore(for: .cpu).width == 6)
        #expect(gates.semaphore(for: .swVideo).width == 1)
    }
}

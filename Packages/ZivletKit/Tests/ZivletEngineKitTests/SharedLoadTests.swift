import Foundation
import Synchronization
import Testing
import ZivletCore

@testable import ZivletEngineKit

@Suite("SharedLoad: one load for concurrent callers, failures retried")
struct SharedLoadTests {
    @Test func concurrentCallersShareOneLoadAndLaterCallersReuseIt() async throws {
        let loads = Mutex(0)
        let shared = SharedLoad<Int>()
        let load: @Sendable () async throws(JobError) -> Int = {
            loads.withLock { $0 += 1 }
            try? await Task.sleep(for: .milliseconds(20))
            return 7
        }
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 { group.addTask { try await shared.value(load) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(values == Array(repeating: 7, count: 10))
        #expect(try await shared.value(load) == 7)
        #expect(loads.withLock { $0 } == 1)
    }

    @Test func aCancelledWaiterStopsWaitingAndTheLoadStillCompletesForOthers() async throws {
        let shared = SharedLoad<Int>()
        let load: @Sendable () async throws(JobError) -> Int = {
            try? await Task.sleep(for: .seconds(1))
            return 7
        }
        let other = Task { try await shared.value(load) }
        let waiter = Task { try await shared.value(load) }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        waiter.cancel()
        await #expect(throws: JobError.cancelled) { try await waiter.value }
        #expect(ContinuousClock.now - start < .milliseconds(300))
        #expect(try await other.value == 7)
    }

    @Test func anAlreadyCancelledCallerDoesNotStartALoad() async {
        let loads = Mutex(0)
        let shared = SharedLoad<Int>()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await shared.value { () async throws(JobError) in
                loads.withLock { $0 += 1 }
                return 1
            }
        }
        await #expect(throws: JobError.cancelled) { try await task.value }
        #expect(loads.withLock { $0 } == 0)
    }

    @Test func aFailureReachesEveryWaiterAndIsNotKept() async throws {
        let attempts = Mutex(0)
        let shared = SharedLoad<Int>()
        let load: @Sendable () async throws(JobError) -> Int = {
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            try? await Task.sleep(for: .milliseconds(10))
            if attempt == 1 { throw .engineMissing(.media) }
            return attempt
        }
        await #expect(throws: JobError.engineMissing(.media)) { try await shared.value(load) }
        #expect(try await shared.value(load) == 2)
        #expect(try await shared.value(load) == 2)
    }
}

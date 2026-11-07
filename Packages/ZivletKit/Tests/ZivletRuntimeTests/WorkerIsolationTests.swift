import EngineTestSupport
import Foundation
import Synchronization
import Testing
import ZivletCore

@testable import ZivletRuntime

/// The worker's shared and exclusive permits (D-M7-60): ordinary work runs together, a retry runs alone once the work in
/// flight has ended, waiters go in first in, first out, a cancelled waiter holds nothing, and a holder's own requests
/// never wait behind its permit.
@Suite("Worker isolation")
struct WorkerIsolationTests {
    /// Records who is inside at once.
    final class Inside: Sendable {
        private let state = Mutex((now: 0, most: 0, order: [String]()))
        func enter(_ name: String) {
            state.withLock {
                $0.now += 1
                $0.most = max($0.most, $0.now)
                $0.order.append(name)
            }
        }
        func leave() { state.withLock { $0.now -= 1 } }
        var most: Int { state.withLock(\.most) }
        var order: [String] { state.withLock(\.order) }
    }

    static func waitForQueue(_ gate: WorkerIsolation, _ count: Int) async {
        while await gate.waiting < count { await Task.yield() }
    }

    @Test func sharedWorkRunsTogether() async throws {
        let gate = WorkerIsolation()
        let inside = Inside()
        let release = Signal()
        let tasks = (0..<3).map { index in
            Task {
                try await gate.shared { () async throws(JobError) in
                    inside.enter("s\(index)")
                    await release.wait()
                    inside.leave()
                }
            }
        }
        while inside.order.count < 3 { await Task.yield() }
        release.fire()
        for task in tasks { try await task.value }
        #expect(inside.most == 3)
    }

    @Test func aRetryWaitsForTheWorkInFlightAndHoldsTheNextBack() async throws {
        let gate = WorkerIsolation()
        let inside = Inside()
        let first = Signal()
        let running = Task {
            try await gate.shared { () async throws(JobError) in
                inside.enter("first")
                await first.wait()
                inside.leave()
            }
        }
        while inside.order.isEmpty { await Task.yield() }
        let retry = Task {
            try await gate.alone { () async throws(JobError) in
                inside.enter("retry")
                inside.leave()
            }
        }
        await Self.waitForQueue(gate, 1)
        let later = Task {
            try await gate.shared { () async throws(JobError) in
                inside.enter("later")
                inside.leave()
            }
        }
        await Self.waitForQueue(gate, 2)
        #expect(inside.order == ["first"])
        first.fire()
        try await running.value
        try await retry.value
        try await later.value
        #expect(inside.order == ["first", "retry", "later"] && inside.most == 1)
    }

    @Test func aCancelledWaiterThrowsAndHoldsNothing() async throws {
        let gate = WorkerIsolation()
        let release = Signal()
        let entered = Signal()
        let holder = Task {
            try await gate.alone { () async throws(JobError) in
                entered.fire()
                await release.wait()
            }
        }
        await entered.wait()
        let waiter = Task { try await gate.shared { () async throws(JobError) in "ran" } }
        await Self.waitForQueue(gate, 1)
        waiter.cancel()
        await #expect(throws: JobError.cancelled) { try await waiter.value }
        release.fire()
        try await holder.value
        #expect(try await gate.alone { () async throws(JobError) in "free" } == "free")
    }

    @Test func aHoldersOwnRequestsDoNotWaitBehindItsPermit() async throws {
        let gate = WorkerIsolation()
        let inner = try await gate.alone { () async throws(JobError) in
            try await gate.shared { () async throws(JobError) in
                try await gate.alone { () async throws(JobError) in 7 }
            }
        }
        #expect(inner == 7)
    }
}

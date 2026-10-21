import Foundation
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// G-15: decoded megapixels in flight across all ImageIO jobs stay under one process-wide budget.
@Suite("Process-wide decode budget (G-15)")
struct DecodeBudgetTests {
    static let megapixel = 1_000_000

    @Test func theThirdOfThree600MPReservationsWaitsForARelease() async throws {
        let budget = DecodeBudget(limit: 1_500 * Self.megapixel)
        let first = try await budget.reserve(600 * Self.megapixel)
        _ = try await budget.reserve(600 * Self.megapixel)
        let granted = Mutex(false)
        let third = Task {
            let reservation = try await budget.reserve(600 * Self.megapixel)
            granted.withLock { $0 = true }
            return reservation
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!granted.withLock { $0 })
        #expect(await budget.inFlight == 1_200 * Self.megapixel)
        #expect(await budget.waiting == 1)
        await budget.release(first)
        _ = try await third.value
        #expect(granted.withLock { $0 })
        #expect(await budget.inFlight == 1_200 * Self.megapixel)
    }

    @Test func cancellingAWaiterLeaksNoBudget() async throws {
        let budget = DecodeBudget(limit: 1_500 * Self.megapixel)
        let held = try await budget.reserve(1_000 * Self.megapixel)
        let waiter = Task { try await budget.reserve(1_000 * Self.megapixel) }
        while await budget.waiting == 0 { try await Task.sleep(for: .milliseconds(5)) }
        waiter.cancel()
        await #expect(throws: JobError.cancelled) { try await waiter.value }
        #expect(await budget.waiting == 0)
        await budget.release(held)
        #expect(await budget.inFlight == 0)
        let whole = try await budget.reserve(1_500 * Self.megapixel)
        #expect(whole.pixels == 1_500 * Self.megapixel)
    }

    @Test func aReservationLargerThanTheBudgetRunsAlone() async throws {
        let budget = DecodeBudget(limit: 100)
        let big = try await budget.reserve(1_000)
        #expect(big.pixels == 100)
        #expect(await budget.inFlight == 100)
        await budget.release(big)
        #expect(await budget.inFlight == 0)
    }

    @Test func anAlreadyCancelledTaskDoesNotQueue() async throws {
        let budget = DecodeBudget(limit: 100)
        let held = try await budget.reserve(100)
        let late = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await budget.reserve(10)
        }
        await #expect(throws: JobError.cancelled) { try await late.value }
        await budget.release(held)
        #expect(await budget.inFlight == 0)
        #expect(await budget.waiting == 0)
    }

    @Test func theEngineReleasesWhatItReservedAfterAConversion() async throws {
        let budget = DecodeBudget(limit: 1_500 * Self.megapixel)
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.opaque(.png, in: dir) }
        _ = try await ImageRun(engine: ImageEngine(budget: budget)).convert(source, .png, to: .jpg, in: dir)
        #expect(await budget.inFlight == 0)
        #expect(DecodeBudget.shared.limit == 1_500 * Self.megapixel)
    }
}

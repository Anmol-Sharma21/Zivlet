import Foundation
import ZivletCore

/// Pixels one job may hold decoded; returned by `DecodeBudget.reserve`, given back with `release`.
public struct DecodeReservation: Sendable, Equatable {
    public let pixels: Int
}

/// Decoded pixels in flight across every ImageIO job of the process (G-15): at most 1,500 MP (about 6 GB of RGBA)
/// together. A job reserves its frame size before decoding and waits, first come first served, while the budget is
/// spent. A reservation above the whole budget is cut to it, so a single big job still runs, alone; one frame over
/// the per-frame cap never gets here (`ImagePlanner` refuses it at plan time). Cancelling a waiter takes it out of
/// the queue and costs nothing.
public actor DecodeBudget {
    public static let processLimit = 1_500_000_000
    public static let shared = DecodeBudget(limit: processLimit)

    private struct Waiter {
        let id: UUID
        let pixels: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    public nonisolated let limit: Int
    public private(set) var inFlight = 0
    private var queue: [Waiter] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public var waiting: Int { queue.count }

    public func reserve(_ pixels: Int) async throws(JobError) -> DecodeReservation {
        let amount = min(max(pixels, 0), limit)
        if Task.isCancelled { throw .cancelled }
        if queue.isEmpty && inFlight + amount <= limit {
            inFlight += amount
            return DecodeReservation(pixels: amount)
        }
        let id = UUID()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    enqueue(Waiter(id: id, pixels: amount, continuation: continuation))
                }
            } onCancel: {
                Task { await self.withdraw(id) }
            }
        } catch {
            throw .cancelled
        }
        return DecodeReservation(pixels: amount)
    }

    public func release(_ reservation: DecodeReservation) {
        inFlight = max(0, inFlight - reservation.pixels)
        grant()
    }

    private func enqueue(_ waiter: Waiter) {
        queue.append(waiter)
        grant()
    }

    /// Wakes waiters in order while the next one fits; its pixels are counted before it resumes.
    private func grant() {
        while let next = queue.first, inFlight + next.pixels <= limit {
            queue.removeFirst()
            inFlight += next.pixels
            next.continuation.resume()
        }
    }

    /// A cancelled waiter leaves the queue; one already granted keeps its reservation (its caller releases it).
    private func withdraw(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
        grant()
    }
}

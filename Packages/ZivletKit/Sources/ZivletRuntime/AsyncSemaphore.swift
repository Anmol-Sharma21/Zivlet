import ZivletCore
import ZivletEngineKit

/// Cancellation-aware counting semaphore (P1-12, 14 §5.2). Waiters are served first in, first out. A waiter whose
/// task is cancelled throws `JobError.cancelled` and never holds a permit. `width` is the configured size; the
/// current `limit` can be lowered (0 pauses admission) or restored at any time, and never preempts a held permit.
public actor AsyncSemaphore {
    struct Waiter {
        let ticket: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    public nonisolated let width: Int
    private var limit: Int
    private var inUse = 0
    private var waiters: [Waiter] = []
    private var nextTicket: UInt64 = 0

    public init(width: Int) {
        self.width = max(1, width)
        self.limit = max(1, width)
    }

    /// New permits are granted only while fewer than `limit` are held.
    public func setLimit(_ newLimit: Int) {
        limit = max(0, newLimit)
        admitWaiters()
    }

    public func acquire() async throws(JobError) {
        if Task.isCancelled { throw .cancelled }
        if inUse < limit, waiters.isEmpty {
            inUse += 1
            return
        }
        let ticket = nextTicket
        nextTicket += 1
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append(Waiter(ticket: ticket, continuation: continuation))
                }
            } onCancel: {
                Task { await self.cancelWaiter(ticket) }
            }
        } catch {
            throw .cancelled
        }
    }

    /// Returns a permit; the oldest waiters take freed permits while the limit allows.
    public func release() {
        inUse = max(0, inUse - 1)
        admitWaiters()
    }

    private func admitWaiters() {
        while inUse < limit, !waiters.isEmpty {
            inUse += 1
            waiters.removeFirst().continuation.resume()
        }
    }

    /// Runs `body` holding one permit; the permit is returned however `body` ends.
    public nonisolated func withPermit<T: Sendable>(_ body: () async throws(JobError) -> T) async throws(JobError) -> T
    {
        try await acquire()
        do {
            let value = try await body()
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }

    var waiting: Int { waiters.count }
    var free: Int { max(0, limit - inUse) }

    /// A waiter that was already granted its permit is not found here, and keeps the permit.
    private func cancelWaiter(_ ticket: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

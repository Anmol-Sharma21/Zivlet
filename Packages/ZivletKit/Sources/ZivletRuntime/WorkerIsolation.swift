import ZivletCore

/// Who may use the worker at once (D-M7-60). One file's stuck qpdf call stops the whole worker (the PDF watchdog can
/// only kill the process), so every job in flight there crashes with it. Ordinary work holds a shared permit; a crash
/// retry holds the worker alone, so a second crash during it can only be its own file's and P2-01's rule names the
/// right file. Waiters are served first in, first out: shared ones that queue behind a retry wait for it, and a retry
/// waits for the work in flight to end. A waiter whose task is cancelled throws `.cancelled` and holds nothing.
///
/// A task that holds a permit makes its worker requests without asking again (`holding`), so a job's own requests never
/// wait behind the permit it holds.
public actor WorkerIsolation {
    enum Kind { case shared, alone }

    struct Waiter {
        let ticket: UInt64
        let kind: Kind
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// The gate whose permit the current task holds, if any.
    @TaskLocal static var holding: WorkerIsolation?

    private var sharedHolders = 0
    private var aloneHeld = false
    private var waiters: [Waiter] = []
    private var nextTicket: UInt64 = 0

    public init() {}

    /// Runs `body` beside other ordinary work; it waits while a retry holds the worker alone.
    public nonisolated func shared<T: Sendable>(_ body: () async throws(JobError) -> T) async throws(JobError) -> T {
        try await held(.shared, body)
    }

    /// Runs `body` with the worker to itself: once the work in flight has ended, and with new work held until it ends.
    public nonisolated func alone<T: Sendable>(_ body: () async throws(JobError) -> T) async throws(JobError) -> T {
        try await held(.alone, body)
    }

    /// Waiters in the queue (tests).
    var waiting: Int { waiters.count }

    private nonisolated func held<T: Sendable>(_ kind: Kind, _ body: () async throws(JobError) -> T)
        async throws(JobError) -> T
    {
        if Self.holding === self { return try await body() }
        try await acquire(kind)
        let result = await Self.$holding.withValue(self) {
            await Result { () async throws(JobError) -> T in try await body() }
        }
        await release(kind)
        return try result.get()
    }

    private func acquire(_ kind: Kind) async throws(JobError) {
        if Task.isCancelled { throw .cancelled }
        if waiters.isEmpty, admits(kind) { return take(kind) }
        let ticket = nextTicket
        nextTicket += 1
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append(Waiter(ticket: ticket, kind: kind, continuation: continuation))
                }
            } onCancel: {
                Task { await self.cancelWaiter(ticket) }
            }
        } catch {
            throw .cancelled
        }
    }

    private func release(_ kind: Kind) {
        switch kind {
        case .shared: sharedHolders = max(0, sharedHolders - 1)
        case .alone: aloneHeld = false
        }
        admitWaiters()
    }

    private func admits(_ kind: Kind) -> Bool {
        switch kind {
        case .shared: !aloneHeld
        case .alone: !aloneHeld && sharedHolders == 0
        }
    }

    private func take(_ kind: Kind) {
        switch kind {
        case .shared: sharedHolders += 1
        case .alone: aloneHeld = true
        }
    }

    /// The oldest waiters go in while they may: a run of shared ones together, or one retry alone.
    private func admitWaiters() {
        while let first = waiters.first, admits(first.kind) {
            take(first.kind)
            waiters.removeFirst().continuation.resume()
        }
    }

    /// A waiter that was already let in is not found here, and keeps its permit.
    private func cancelWaiter(_ ticket: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        admitWaiters()
    }
}

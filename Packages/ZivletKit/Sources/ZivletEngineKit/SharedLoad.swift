import ZivletCore

/// A value loaded once and shared. Callers that arrive while a load runs wait for that same load instead of starting
/// another (actors are reentrant across `await`, so a plain "if cached" check lets every early caller spawn its own
/// probe). A success is kept; a failure reaches every waiter and is forgotten, so the next call tries again.
/// A waiter whose task is cancelled stops waiting at once with `JobError.cancelled`; the load itself carries on for
/// the others (a cancelled conversion must not wait for a capability probe to finish).
public actor SharedLoad<Value: Sendable> {
    private typealias Waiter = CheckedContinuation<Result<Value, JobError>, Never>

    private var loaded: Value?
    private var isLoading = false
    private var waiters: [UInt64: Waiter] = [:]
    private var nextTicket: UInt64 = 0

    public init() {}

    public func value(_ load: @escaping @Sendable () async throws(JobError) -> Value) async throws(JobError) -> Value {
        if let loaded { return loaded }
        if Task.isCancelled { throw .cancelled }
        let ticket = nextTicket
        nextTicket += 1
        if !isLoading { start(load) }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { waiters[ticket] = $0 }
        } onCancel: {
            Task { await self.cancelWaiter(ticket) }
        }
        return try result.get()
    }

    private func start(_ load: @escaping @Sendable () async throws(JobError) -> Value) {
        isLoading = true
        Task.detached {
            let result = await Result.capturing(load)
            await self.finish(result)
        }
    }

    private func finish(_ result: Result<Value, JobError>) {
        isLoading = false
        if case .success(let value) = result { loaded = value }
        let waiting = waiters.values
        waiters = [:]
        for waiter in waiting { waiter.resume(returning: result) }
    }

    /// A waiter already resumed by `finish` is not found here and keeps its result.
    private func cancelWaiter(_ ticket: UInt64) {
        waiters.removeValue(forKey: ticket)?.resume(returning: .failure(.cancelled))
    }
}

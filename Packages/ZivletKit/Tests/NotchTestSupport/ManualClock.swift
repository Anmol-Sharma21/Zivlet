import Synchronization
import ZivletNotch

/// A clock the test moves by hand. Sleepers wake when the test advances past their deadline, or early once with
/// `wakeEarly(by:)`, which is what a wake from system sleep can look like to a sleeping task.
public final class ManualClock: MonotonicClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Duration.zero
        var sleepers: [Int: Sleeper] = [:]
        var nextID = 0
    }

    private let state = Mutex(State())

    public init() {}

    public func now() -> Duration { state.withLock { $0.now } }

    public var pendingSleepers: Int { state.withLock { $0.sleepers.count } }

    public func sleep(until deadline: Duration) async throws {
        let id = state.withLock { s in
            defer { s.nextID += 1 }
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let ready = state.withLock { s in
                    guard s.now < deadline else { return true }
                    s.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return false
                }
                if ready { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.sleepers.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has come, then lets their tasks run.
    public func advance(by step: Duration) async {
        let woken = state.withLock { s -> [Sleeper] in
            s.now += step
            let due = s.sleepers.filter { $0.value.deadline <= s.now }
            for id in due.keys { s.sleepers[id] = nil }
            return Array(due.values)
        }
        for sleeper in woken { sleeper.continuation.resume() }
        await Self.settle()
    }

    /// Wakes the earliest sleeper `early` before its deadline (time moves to that moment), then lets it run.
    public func wakeEarly(by early: Duration) async {
        let woken = state.withLock { s -> Sleeper? in
            guard let (id, first) = s.sleepers.min(by: { $0.value.deadline < $1.value.deadline }) else { return nil }
            s.sleepers[id] = nil
            s.now = max(s.now, first.deadline - early)
            return first
        }
        woken?.continuation.resume()
        await Self.settle()
    }

    /// Enough turns of the caller's actor for woken tasks to finish their step.
    public static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

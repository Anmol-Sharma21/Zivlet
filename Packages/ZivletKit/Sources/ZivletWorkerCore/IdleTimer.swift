import Foundation
import Synchronization

/// Fires `onIdle` once `after` has passed since the last `arm()`, unless `disarm()` or another `arm()` came first
/// (D-M6-10: launchd keeps an idle worker alive, so the worker exits on its own). Each arm starts a new generation;
/// a sleep that ends in an old generation does nothing. The sleeper is injected so tests drive time.
public final class IdleTimer: Sendable {
    public typealias Sleeper = @Sendable (Duration) async -> Void

    public static let realSleep: Sleeper = { duration in try? await Task.sleep(for: duration) }

    private struct State {
        var generation = 0
        var interval: Duration
        var sleeping: Task<Void, Never>?
    }

    private let state: Mutex<State>
    private let sleep: Sleeper
    private let onIdle: @Sendable () -> Void

    public init(
        after interval: Duration, sleep: @escaping Sleeper = IdleTimer.realSleep, onIdle: @escaping @Sendable () -> Void
    ) {
        state = Mutex(State(interval: interval))
        self.sleep = sleep
        self.onIdle = onIdle
    }

    public var interval: Duration { state.withLock(\.interval) }

    /// A shorter idle time for the smoke run; takes effect at the next arm.
    public func setInterval(_ interval: Duration) {
        state.withLock { $0.interval = interval }
    }

    public func arm() {
        let (generation, interval, previous) = state.withLock { state in
            state.generation += 1
            defer { state.sleeping = nil }
            return (state.generation, state.interval, state.sleeping)
        }
        previous?.cancel()
        let task = Task { [sleep] in
            await sleep(interval)
            self.fire(ifStill: generation)
        }
        state.withLock { state in
            if state.generation == generation { state.sleeping = task }
        }
    }

    public func disarm() {
        let previous = state.withLock { state in
            state.generation += 1
            defer { state.sleeping = nil }
            return state.sleeping
        }
        previous?.cancel()
    }

    private func fire(ifStill generation: Int) {
        let current = state.withLock { state in
            guard state.generation == generation else { return false }
            state.generation += 1
            state.sleeping = nil
            return true
        }
        if current { onIdle() }
    }
}

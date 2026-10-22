import Foundation

/// The island's one clock (D-N11): `now` and every deadline sleep use it, so a linger that spans system sleep has
/// passed on wake. Times are durations since the clock's origin; deadlines are absolute on the same scale.
nonisolated public protocol MonotonicClock: Sendable {
    func now() -> Duration
    /// Returns at or after `deadline`, or earlier when the system wakes a sleeper early; callers check `now()` again.
    func sleep(until deadline: Duration) async throws
}

/// `ContinuousClock`, which keeps counting while the Mac sleeps.
nonisolated public struct SystemClock: MonotonicClock {
    private let origin: ContinuousClock.Instant

    public init(origin: ContinuousClock.Instant = .now) { self.origin = origin }

    public func now() -> Duration { origin.duration(to: .now) }

    public func sleep(until deadline: Duration) async throws {
        try await Task.sleep(until: origin.advanced(by: deadline), clock: .continuous)
    }
}

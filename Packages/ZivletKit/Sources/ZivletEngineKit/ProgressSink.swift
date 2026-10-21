import Foundation
import Synchronization
import ZivletCore

/// Engine → runtime progress channel (02 §6.2, 03a §4.5): throttled to one delivery per `interval` (10 Hz), fractions
/// never decrease (a lower one is dropped), the first report and the final 1.0 always pass, and indeterminate
/// (bytes-only) progress passes at the same rate until a fraction is known. Safe to call from any thread.
public struct ProgressSink: Sendable {
    public static let discard = ProgressSink { _ in }

    private let gate: ProgressGate

    public init(
        clock: @escaping @Sendable () -> Duration = ProgressSink.uptime, interval: Duration = .milliseconds(100),
        deliver: @escaping @Sendable (JobProgress) -> Void
    ) {
        gate = ProgressGate(clock: clock, interval: interval, deliver: deliver)
    }

    public func report(_ fraction: Double?) { gate.offer(JobProgress(fraction: fraction)) }

    /// Stage, bytes and ETA as well; the same throttle and monotonic rule apply.
    public func report(_ progress: JobProgress) { gate.offer(progress) }

    /// Monotonic time since boot, the default clock.
    public static func uptime() -> Duration {
        .nanoseconds(Int64(clamping: DispatchTime.now().uptimeNanoseconds))
    }
}

/// The mutable part of a sink: last delivered value and time, guarded by a mutex.
private final class ProgressGate: Sendable {
    struct Last {
        var fraction: Double?
        var at: Duration?
    }

    let clock: @Sendable () -> Duration
    let interval: Duration
    let deliver: @Sendable (JobProgress) -> Void
    let last = Mutex(Last())

    init(
        clock: @escaping @Sendable () -> Duration, interval: Duration,
        deliver: @escaping @Sendable (JobProgress) -> Void
    ) {
        self.clock = clock
        self.interval = interval
        self.deliver = deliver
    }

    func offer(_ progress: JobProgress) {
        let now = clock()
        let admitted = last.withLock { last -> Bool in
            guard Self.admits(progress, last: last, now: now, interval: interval) else { return false }
            last = Last(fraction: progress.fraction ?? last.fraction, at: now)
            return true
        }
        if admitted { deliver(progress) }
    }

    private static func admits(_ progress: JobProgress, last: Last, now: Duration, interval: Duration) -> Bool {
        guard let at = last.at else { return true }
        // Bytes-only progress (unknown duration) passes until a positive fraction has been delivered.
        guard let fraction = progress.fraction else { return (last.fraction ?? 0) == 0 && now - at >= interval }
        if let previous = last.fraction, fraction <= previous { return false }
        return fraction >= 1 || now - at >= interval
    }
}

import Synchronization
import ZivletCore
import ZivletEngineKit

/// When an encode counts as stuck (03a §4.6): `out_time` flat for `limit`, checked every `interval`.
public struct StallPolicy: Sendable {
    public static let standard = StallPolicy(limit: .seconds(60), interval: .seconds(1))

    public let limit: Duration
    public let interval: Duration
    public let clock: @Sendable () -> Duration

    public init(
        limit: Duration, interval: Duration, clock: @escaping @Sendable () -> Duration = ProgressSink.uptime
    ) {
        self.limit = limit
        self.interval = interval
        self.clock = clock
    }
}

/// Pure stall detector (P1-07): remembers when `out_time` last moved forward. Until the first `out_time` arrives,
/// `startupLimit` (never shorter than `limit`) applies, for passes that write nothing until they have read their
/// whole input.
public struct StallWatch: Sendable, Equatable {
    let limit: Duration
    let startupLimit: Duration
    let lastAdvance: Duration
    let outTimeMicros: Int64?

    public init(limit: Duration, start: Duration, startupLimit: Duration? = nil) {
        self.init(
            limit: limit, startupLimit: max(limit, startupLimit ?? limit), lastAdvance: start, outTimeMicros: nil)
    }

    private init(limit: Duration, startupLimit: Duration, lastAdvance: Duration, outTimeMicros: Int64?) {
        self.limit = limit
        self.startupLimit = startupLimit
        self.lastAdvance = lastAdvance
        self.outTimeMicros = outTimeMicros
    }

    /// A larger `out_time` resets the watch; a repeated or missing one does not.
    public func observing(outTimeMicros time: Int64?, at now: Duration) -> StallWatch {
        guard let time, time > (outTimeMicros ?? -1) else { return self }
        return StallWatch(limit: limit, startupLimit: startupLimit, lastAdvance: now, outTimeMicros: time)
    }

    public func isStalled(at now: Duration) -> Bool {
        now - lastAdvance >= (outTimeMicros == nil ? startupLimit : limit)
    }
}

/// Runs one ffmpeg launch beside a watchdog. A stall cancels the launch (the runner tears the process group down)
/// and the run fails with `stalled`; otherwise the launch's own result or error comes back.
final class StallMonitor: Sendable {
    let policy: StallPolicy
    private let watch: Mutex<StallWatch>

    init(policy: StallPolicy, startupLimit: Duration? = nil) {
        self.policy = policy
        watch = Mutex(StallWatch(limit: policy.limit, start: policy.clock(), startupLimit: startupLimit))
    }

    func observe(_ event: FFmpegProgressEvent) {
        let now = policy.clock()
        watch.withLock { $0 = $0.observing(outTimeMicros: event.outTimeMicros, at: now) }
    }

    func guarding<T: Sendable>(_ body: @escaping @Sendable () async throws(JobError) -> T) async throws(JobError) -> T {
        let outcome = await withTaskGroup(of: Result<T, JobError>?.self) { group in
            group.addTask { await Result.capturing(body) }
            group.addTask { await self.watchdog() }
            var first: Result<T, JobError>?
            while first == nil, let next = await group.next() { first = next }
            group.cancelAll()
            return first
        }
        guard let outcome else { throw .cancelled }
        return try outcome.get()
    }

    /// Nil when cancelled because the launch finished first.
    private func watchdog<T>() async -> Result<T, JobError>? {
        while !Task.isCancelled {
            try? await Task.sleep(for: policy.interval)
            let now = policy.clock()
            if !Task.isCancelled, watch.withLock({ $0.isStalled(at: now) }) { return .failure(.stalled) }
        }
        return nil
    }
}

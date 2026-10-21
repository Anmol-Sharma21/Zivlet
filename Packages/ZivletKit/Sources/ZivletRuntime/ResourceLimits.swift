import Darwin
import os

/// The process's open-file limit (G-18). macOS starts apps at a soft limit of 256 descriptors; a large batch with
/// helpers, pipes, image sources and job records can pass that, so launch raises it toward 4,096, capped by the hard
/// limit, and never lowers it.
public enum ResourceLimits {
    public static let wantedOpenFiles: rlim_t = 4_096
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

    public struct Change: Sendable, Equatable {
        public let old: rlim_t
        public let new: rlim_t
    }

    public static func openFiles() -> (soft: rlim_t, hard: rlim_t)? {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return nil }
        return (limit.rlim_cur, limit.rlim_max)
    }

    /// Raises the soft limit to `min(hard, wanted)` when that is higher; logs both values. Nil when the limit cannot
    /// be read or set.
    @discardableResult
    public static func raiseOpenFiles(to wanted: rlim_t = wantedOpenFiles) -> Change? {
        guard let (soft, hard) = openFiles() else {
            logger.error("Open-file limit unreadable: errno \(errno, privacy: .public)")
            return nil
        }
        let target = target(soft: soft, hard: hard, wanted: wanted)
        guard target > soft else { return Change(old: soft, new: soft) }
        var limit = rlimit(rlim_cur: target, rlim_max: hard)
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            logger.error("Open-file limit not raised from \(soft, privacy: .public): errno \(errno, privacy: .public)")
            return nil
        }
        logger.info("Open-file limit raised from \(soft, privacy: .public) to \(target, privacy: .public)")
        return Change(old: soft, new: target)
    }

    /// `min(hard, wanted)`, but never below the current soft limit.
    static func target(soft: rlim_t, hard: rlim_t, wanted: rlim_t) -> rlim_t {
        max(soft, min(hard, wanted))
    }
}

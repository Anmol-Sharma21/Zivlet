import Darwin

/// CPU time of the calling thread (D-M7-4): what a piece of work costs on, say, the main thread, which a loaded
/// scheduler cannot inflate, since time spent waiting for a core is not counted.
public enum ThreadCPUTime {
    /// The calling thread's CPU time spent in `work`.
    public static func measure(_ work: () throws -> Void) rethrows -> Duration {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        try work()
        let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        return .nanoseconds(Int64(end - start))
    }
}

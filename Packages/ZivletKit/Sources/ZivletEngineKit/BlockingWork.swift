import Foundation
import Synchronization
import ZivletCore

/// Set when the task that started some blocking work is cancelled; the work polls it between frames or pages.
public final class CancellationFlag: Sendable {
    private let state = Mutex(false)

    public init() {}

    public var isCancelled: Bool { state.withLock { $0 } }

    public func cancel() { state.withLock { $0 = true } }
}

/// Runs blocking framework calls (ImageIO encoders, Quartz) on a GCD thread, never on the Swift cooperative pool:
/// concurrent AVIF encodes on the pool deadlock on macOS 27 (index D-M3-10). Cancelling the calling task sets the
/// flag passed to `work`.
public enum BlockingWork {
    public static func run<T: Sendable>(
        _ work: @escaping @Sendable (CancellationFlag) throws(JobError) -> T
    ) async throws(JobError) -> T {
        let flag = CancellationFlag()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<T, JobError>, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Result { () throws(JobError) -> T in try work(flag) })
                }
            }
        } onCancel: {
            flag.cancel()
        }
        return try result.get()
    }
}

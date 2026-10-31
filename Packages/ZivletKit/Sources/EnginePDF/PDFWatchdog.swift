import Dispatch
import Synchronization
import ZivletEngineKit

/// The per-job watchdog of blocking qpdf calls (10 §8.3, D-M7-18). A call inside the library cannot be cancelled, so
/// one that outlives its budget has only one way out: `onStuck`, which in the worker stops the process. The app then
/// sees a crashed worker, retries once, and blames the file the second time (P2-01's rule).
///
/// qpdf runs one call at a time (D-M7-32), so steps take turns here and a step's budget starts when its turn comes: a
/// small job waiting behind a large one spends nothing, and cannot stop the worker while the large one is working.
public struct PDFWatchdog: Sendable {
    /// Starts a one-shot timer that calls its second argument after the first, and returns what stops it.
    public typealias Schedule = @Sendable (Duration, @escaping @Sendable () -> Void) -> @Sendable () -> Void

    private static let turn = Mutex(())

    private let schedule: Schedule?
    private let onStuck: @Sendable () -> Void

    public init(schedule: @escaping Schedule = PDFWatchdog.dispatchTimer, onStuck: @escaping @Sendable () -> Void) {
        self.schedule = schedule
        self.onStuck = onStuck
    }

    private init() {
        schedule = nil
        onStuck = {}
    }

    /// Takes turns but arms no timer: tools and tests that run qpdf outside the worker.
    public static let off = PDFWatchdog()

    /// Runs `step` when its turn comes, with a budget for an input of `inputBytes`.
    public func guarding<Value: Sendable>(
        inputBytes: Int64, _ step: () throws(PDFEngineError) -> Value
    ) throws(PDFEngineError) -> Value {
        try Self.turn.withLock { _ throws(PDFEngineError) -> sending Value in
            let disarm = schedule?(PDFLimits.watchdogBudget(inputBytes: inputBytes), onStuck)
            defer { disarm?() }
            return try step()
        }
    }

    /// A Dispatch timer. Its clock stops while the Mac sleeps, so waking up does not stop a job.
    public static let dispatchTimer: Schedule = { budget, fire in
        let milliseconds = Int((budget / .milliseconds(1)).rounded(.up))
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(milliseconds))
        timer.setEventHandler(handler: fire)
        timer.resume()
        return { timer.cancel() }
    }
}

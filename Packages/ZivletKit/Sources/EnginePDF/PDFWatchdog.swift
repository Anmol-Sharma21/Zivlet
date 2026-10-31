import Darwin
import Dispatch
import Synchronization
import ZivletEngineKit

/// The per-job watchdog of blocking qpdf calls (10 §8.3, D-M7-18, D-M7-44). A call inside the library cannot be
/// cancelled, so one that outlives its budget or outgrows its memory ceiling has only one way out: `onStuck`, which in
/// the worker stops the process. The app then sees a crashed worker, retries once, and blames the file the second time
/// (P2-01's rule).
///
/// qpdf runs one call at a time (D-M7-32), so steps take turns here and a step's budget starts when its turn comes: a
/// small job waiting behind a large one spends nothing, and cannot stop the worker while the large one is working.
///
/// The ceiling is on the whole process, not on a step's growth. malloc keeps what an earlier step freed and that counts
/// as footprint, so growth would hide a later step's memory and a batch of crafted files could climb past any limit on
/// it. Another job's memory counts too: at worst that costs one retry, which is the cheaper mistake.
public struct PDFWatchdog: Sendable {
    /// Starts a timer that calls its second argument after the first (once, or every time for a poll), and returns what
    /// stops it.
    public typealias Schedule = @Sendable (Duration, @escaping @Sendable () -> Void) -> @Sendable () -> Void
    /// The process's memory footprint in bytes, or nil when it cannot be read.
    public typealias Footprint = @Sendable () -> Int64?

    private static let turn = Mutex(())

    private let schedule: Schedule?
    private let poll: Schedule?
    private let footprint: Footprint
    private let memoryCeiling: Int64
    private let onStuck: @Sendable () -> Void

    public init(
        schedule: @escaping Schedule = PDFWatchdog.dispatchTimer, poll: @escaping Schedule = PDFWatchdog.dispatchPoll,
        footprint: @escaping Footprint = PDFWatchdog.processFootprint,
        memoryCeiling: Int64 = PDFLimits.maxWorkerFootprint, onStuck: @escaping @Sendable () -> Void
    ) {
        self.schedule = schedule
        self.poll = poll
        self.footprint = footprint
        self.memoryCeiling = memoryCeiling
        self.onStuck = onStuck
    }

    private init() {
        schedule = nil
        poll = nil
        footprint = { nil }
        memoryCeiling = 0
        onStuck = {}
    }

    /// Takes turns but arms no timer: tools and tests that run qpdf outside the worker.
    public static let off = PDFWatchdog()

    /// Runs `step` when its turn comes, with a budget for an input of `inputBytes`. Wrap a whole step once: a step that
    /// called this again would wait for its own turn forever.
    public func guarding<Value: Sendable>(
        inputBytes: Int64, _ step: () throws(PDFEngineError) -> Value
    ) throws(PDFEngineError) -> Value {
        try Self.turn.withLock { _ throws(PDFEngineError) -> sending Value in
            let disarm = schedule?(PDFLimits.watchdogBudget(inputBytes: inputBytes), onStuck)
            let stopPolling = watchMemory()
            defer {
                disarm?()
                stopPolling?()
            }
            return try step()
        }
    }

    /// Polls for a footprint past the ceiling; a reading that fails is not one.
    private func watchMemory() -> (@Sendable () -> Void)? {
        let (footprint, ceiling, onStuck) = (footprint, memoryCeiling, onStuck)
        return poll?(PDFLimits.memoryPollInterval) {
            guard let now = footprint(), now > ceiling else { return }
            onStuck()
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

    /// A repeating Dispatch timer.
    public static let dispatchPoll: Schedule = { interval, tick in
        let milliseconds = Int((interval / .milliseconds(1)).rounded(.up))
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(milliseconds), repeating: .milliseconds(milliseconds))
        timer.setEventHandler(handler: tick)
        timer.resume()
        return { timer.cancel() }
    }

    /// This process's footprint: what the system counts against it under memory pressure.
    public static let processFootprint: Footprint = {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { words in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), words, &count)
            }
        }
        return status == KERN_SUCCESS ? Int64(info.phys_footprint) : nil
    }
}

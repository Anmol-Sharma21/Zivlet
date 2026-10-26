import AppKit
import os

/// What receiving file promises gave: the files written into the box's folder and how many failed.
nonisolated public struct PromiseOutcome: Equatable, Sendable {
    public let received: [URL]
    public let failed: Int

    public init(received: [URL], failed: Int) {
        self.received = received
        self.failed = failed
    }
}

/// Receives file promises (Mail, Photos, browsers) into the box's folder (D-M5b-5). Only inside
/// `performDragOperation`: AppKit raises when promises are received outside a real drag session, so the system
/// receiver is exercised by the QA rows and tests use a fake.
public protocol PromiseReceiving {
    func hasPromises(on pasteboard: NSPasteboard) -> Bool
    func receivePromises(from pasteboard: NSPasteboard, into folder: URL) async -> PromiseOutcome
}

/// `NSFilePromiseReceiver`, one callback per promised file, on a private queue. The wait is bounded: it ends when
/// every named file has called back, after a quiet moment when a receiver did not name its files, or at a deadline,
/// with whatever arrived and the rest counted as failed. Late callbacks are ignored, and each failure is logged by
/// its error domain and code (never a name or path).
public final class SystemPromiseReceiver: PromiseReceiving {
    nonisolated static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.zivlet.box.promises"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    public init() {}

    public func hasPromises(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }

    public func receivePromises(from pasteboard: NSPasteboard, into folder: URL) async -> PromiseOutcome {
        let receivers =
            pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]
            ?? []
        let expected = receivers.reduce(0) { $0 + max(1, $1.fileNames.count) }
        guard expected > 0 else { return PromiseOutcome(received: [], failed: 0) }
        let named = receivers.allSatisfy { !$0.fileNames.isEmpty }
        let outcome = await withCheckedContinuation { continuation in
            let collector = PromiseCollector(
                expected: expected, named: named, schedule: Self.schedule,
                finish: { continuation.resume(returning: $0) })
            collector.start()
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) {
                    @Sendable url, error in
                    if let error { Self.log(error) }
                    collector.add(error == nil ? url : nil)
                }
            }
        }
        withExtendedLifetime(receivers) {}
        return outcome
    }

    nonisolated private static func log(_ error: any Error) {
        let error = error as NSError
        logger.error(
            "Drop Box promise failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
    }

    nonisolated private static let schedule: @Sendable (Double, @escaping @Sendable () -> Void) -> Void = {
        delay, work in
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Gathers the promise callbacks, which arrive on the receiver's queue, and finishes exactly once: when every named
/// file called back; after `quiet` seconds without a callback once the expected count is reached, when a receiver
/// did not name its files (so extra files still count); or at the deadline, with the missing ones failed.
nonisolated final class PromiseCollector: @unchecked Sendable {
    /// Seconds without a callback that end the wait for unnamed promises.
    static let quiet = 0.5
    /// The longest wait: 15 s, plus 5 s per expected file, at most two minutes.
    static func deadline(expected: Int) -> Double { min(120, 15 + 5 * Double(expected)) }

    private let lock = NSLock()
    private let expected: Int
    private let named: Bool
    private let schedule: @Sendable (Double, @escaping @Sendable () -> Void) -> Void
    private let finish: @Sendable (PromiseOutcome) -> Void
    private var received: [URL] = []
    private var failed = 0
    private var done = false
    private var generation = 0

    init(
        expected: Int, named: Bool, schedule: @escaping @Sendable (Double, @escaping @Sendable () -> Void) -> Void,
        finish: @escaping @Sendable (PromiseOutcome) -> Void
    ) {
        self.expected = expected
        self.named = named
        self.schedule = schedule
        self.finish = finish
    }

    /// Starts the deadline.
    func start() {
        schedule(Self.deadline(expected: expected)) { [self] in deadlinePassed() }
    }

    func add(_ url: URL?) {
        let (outcome, quietGeneration): (PromiseOutcome?, Int?) = lock.withLock {
            guard !done else { return (nil, nil) }
            if let url { received.append(url) } else { failed += 1 }
            guard received.count + failed >= expected else { return (nil, nil) }
            if named { return (end(), nil) }
            generation += 1
            return (nil, generation)
        }
        if let outcome { finish(outcome) }
        if let quietGeneration { schedule(Self.quiet) { [self] in quietPassed(quietGeneration) } }
    }

    func quietPassed(_ seen: Int) {
        let outcome: PromiseOutcome? = lock.withLock { !done && seen == generation ? end() : nil }
        if let outcome { finish(outcome) }
    }

    func deadlinePassed() {
        let outcome: PromiseOutcome? = lock.withLock {
            guard !done else { return nil }
            failed += max(0, expected - received.count - failed)
            return end()
        }
        if let outcome { finish(outcome) }
    }

    /// Under the lock: marks the collector done and returns what it gathered.
    private func end() -> PromiseOutcome {
        done = true
        return PromiseOutcome(received: received, failed: failed)
    }
}

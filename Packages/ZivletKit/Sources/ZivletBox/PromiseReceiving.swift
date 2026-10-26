import AppKit

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

/// `NSFilePromiseReceiver`, one callback per promised file, on a private queue.
public final class SystemPromiseReceiver: PromiseReceiving {
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
        let collector = PromiseCollector(expected: expected)
        return await withCheckedContinuation { continuation in
            collector.finish = { continuation.resume(returning: $0) }
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) {
                    @Sendable url, error in
                    collector.add(error == nil ? url : nil)
                }
            }
        }
    }
}

/// Gathers the promise callbacks, which arrive on the receiver's queue, and finishes once with all of them.
nonisolated private final class PromiseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let expected: Int
    private var received: [URL] = []
    private var failed = 0
    var finish: @Sendable (PromiseOutcome) -> Void = { _ in }

    init(expected: Int) { self.expected = expected }

    func add(_ url: URL?) {
        let outcome: PromiseOutcome? = lock.withLock {
            if let url { received.append(url) } else { failed += 1 }
            return received.count + failed == expected ? PromiseOutcome(received: received, failed: failed) : nil
        }
        if let outcome { finish(outcome) }
    }
}

import Dispatch
import Foundation
import Synchronization
@preconcurrency import XPC
import ZivletCore
import ZivletIPC
import os

/// The worker's XPC glue (P2-01, R4): accepts sessions, decodes each `Envelope<WorkerRequest>`, answers through
/// `WorkerService` on a concurrent queue (`handoffReply`, so a long step never blocks the session's queue and a
/// cancel can arrive meanwhile) and sends `WorkerEvent`s over the same session before the step's reply. A message of
/// another protocol version is answered `.failed(.engineDamaged(.worker))`.
public enum WorkerXPCHost {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    static let replies = DispatchQueue(label: "app.zivlet.Zivlet.Worker.replies", attributes: .concurrent)

    /// The named service in the worker bundle, with the app's peer requirement.
    public static func listen(service: WorkerService, requirement: PeerRequirementSpec) throws -> XPCListener {
        try XPCListener(service: WorkerPeerPolicy.workerServiceName, requirement: requirement.xpcRequirement) {
            request in accept(request, service: service)
        }
    }

    /// An anonymous listener in this process, for tests: connect with `XPCSession(endpoint:)`.
    public static func anonymous(service: WorkerService) -> XPCListener {
        XPCListener { request in accept(request, service: service) }
    }

    static func accept(_ request: XPCListener.IncomingSessionRequest, service: WorkerService)
        -> XPCListener.IncomingSessionRequest.Decision
    {
        let session = SessionBox()
        let (decision, accepted) = request.accept(
            incomingMessageHandler: { (message: XPCReceivedMessage) -> (any Encodable)? in
                answer(message, service: service, session: session)
            },
            cancellationHandler: { _ in logger.notice("The app ended its worker session") })
        session.set(accepted)
        return decision
    }

    private static func answer(_ message: XPCReceivedMessage, service: WorkerService, session: SessionBox)
        -> (any Encodable)?
    {
        let request: WorkerRequest
        do {
            request = try message.decode(as: Envelope<WorkerRequest>.self).body
        } catch let error as WorkerProtocolError {
            return Envelope(WorkerReply.failed(error.jobError))
        } catch {
            logger.error("Undecodable worker request: \(String(describing: error), privacy: .private)")
            return Envelope(WorkerReply.failed(.internalInvariant("The worker could not read a request.")))
        }
        let pending = PendingReply(message)
        return message.handoffReply(to: replies) {
            let reply = blockingHandle(request, service: service) { event in session.send(Envelope(event)) }
            pending.message.reply(Envelope(reply))
        }
    }

    /// Runs the async handler and waits for it on this (GCD) thread, never on the cooperative pool.
    private static func blockingHandle(
        _ request: WorkerRequest, service: WorkerService, events: @escaping WorkerService.EventSink
    ) -> WorkerReply {
        let done = DispatchSemaphore(value: 0)
        let result = Mutex(WorkerReply.failed(.internalInvariant("The worker gave no reply.")))
        Task {
            let reply = await service.handle(request, events: events)
            result.withLock { $0 = reply }
            done.signal()
        }
        done.wait()
        return result.withLock { $0 }
    }
}

/// The accepted session, set once right after `accept` returns (before any message is delivered).
final class SessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var session: XPCSession?

    func set(_ session: XPCSession) {
        lock.withLock { self.session = session }
    }

    func send(_ envelope: Envelope<WorkerEvent>) {
        let session = lock.withLock { self.session }
        do {
            try session?.send(envelope)
        } catch {
            WorkerXPCHost.logger.error("Worker event not sent: \(String(describing: error), privacy: .private)")
        }
    }
}

/// `XPCReceivedMessage` is not `Sendable`; it is only used again to send its one reply.
struct PendingReply: @unchecked Sendable {
    let message: XPCReceivedMessage

    init(_ message: XPCReceivedMessage) { self.message = message }
}

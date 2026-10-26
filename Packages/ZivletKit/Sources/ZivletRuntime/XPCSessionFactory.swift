import Dispatch
import Foundation
import Synchronization
@preconcurrency import XPC
import ZivletCore
import ZivletIPC
import os

/// The app's XPC transport to `ZivletWorker.xpc` (P2-01, D-M6-2, R4). Each session gets its own serial queue, so the
/// worker's events and the replies arrive in the order the worker sent them. Any end of the session fails the
/// calls in flight with `.workerCrashed`; a reply of another protocol version is a damaged worker.
public struct XPCSessionFactory: WorkerTransport {
    enum Target: @unchecked Sendable {
        case service(String, PeerRequirementSpec)
        case endpoint(XPCEndpoint)
    }

    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    let target: Target

    /// The embedded worker, with the peer requirement from this app's own signature (D-M6-7).
    public init(requirement: PeerRequirementSpec) {
        target = .service(WorkerPeerPolicy.workerServiceName, requirement)
    }

    /// A listener's endpoint (tests: an anonymous listener in the test process).
    public init(endpoint: XPCEndpoint) {
        target = .endpoint(endpoint)
    }

    public func open(onEvent: @escaping @Sendable (WorkerEvent) -> Void, onClosed: @escaping @Sendable () -> Void)
        throws(JobError) -> any WorkerChannel
    {
        let queue = DispatchQueue(label: "app.zivlet.Zivlet.worker-session")
        let channel = XPCChannel()
        let incoming: @Sendable (XPCReceivedMessage) -> (any Encodable)? = { message in
            if let event = try? message.decode(as: Envelope<WorkerEvent>.self) { onEvent(event.body) }
            return nil
        }
        let cancelled: @Sendable (XPCRichError) -> Void = { error in
            Self.logger.notice("Worker session ended: \(String(describing: error), privacy: .private)")
            channel.markClosed()
            onClosed()
        }
        do {
            let session: XPCSession
            switch target {
            case .service(let name, let requirement):
                session = try XPCSession(
                    xpcService: name, targetQueue: queue, requirement: requirement.xpcRequirement,
                    incomingMessageHandler: incoming, cancellationHandler: cancelled)
            case .endpoint(let endpoint):
                session = try XPCSession(
                    endpoint: endpoint, targetQueue: queue, incomingMessageHandler: incoming,
                    cancellationHandler: cancelled)
            }
            channel.attach(session)
        } catch {
            Self.logger.error("Worker session not opened: \(String(describing: error), privacy: .private)")
            throw .engineMissing(.worker)
        }
        return channel
    }
}

/// One XPC session as a `WorkerChannel`. It keeps its own table of calls in flight and fails them when the session
/// ends or the app closes it, so the contract holds whether or not XPC still calls their reply handlers.
final class XPCChannel: WorkerChannel, @unchecked Sendable {
    typealias Waiter = CheckedContinuation<Result<WorkerReply, JobError>, Never>

    private struct State {
        var session: XPCSession?
        var closed = false
        var waiting: [UUID: Waiter] = [:]
    }

    private let state = Mutex(State())

    func attach(_ session: XPCSession) {
        state.withLock { $0.session = session }
    }

    /// The session ended: every call in flight fails with `.workerCrashed`.
    func markClosed() {
        let waiting = state.withLock { state in
            state.closed = true
            defer { state.waiting = [:] }
            return Array(state.waiting.values)
        }
        waiting.forEach { $0.resume(returning: .failure(.workerCrashed)) }
    }

    func send(_ request: WorkerRequest) async throws(JobError) -> WorkerReply {
        let call = UUID()
        let result = await withCheckedContinuation { (waiter: Waiter) in
            let session = state.withLock { state -> XPCSession? in
                guard !state.closed, let session = state.session else { return nil }
                state.waiting[call] = waiter
                return session
            }
            guard let session else { return waiter.resume(returning: .failure(.workerCrashed)) }
            do {
                try session.send(Envelope(request)) { (reply: Result<XPCReceivedMessage, XPCRichError>) in
                    self.finish(call, with: Self.decode(reply))
                }
            } catch {
                finish(call, with: .failure(.workerCrashed))
            }
        }
        return try result.get()
    }

    private func finish(_ call: UUID, with result: Result<WorkerReply, JobError>) {
        state.withLock { $0.waiting.removeValue(forKey: call) }?.resume(returning: result)
    }

    func close() {
        let session = state.withLock(\.session)
        markClosed()
        session?.cancel(reason: "The app closed its worker session.")
    }

    static func decode(_ reply: Result<XPCReceivedMessage, XPCRichError>) -> Result<WorkerReply, JobError> {
        guard case .success(let message) = reply else { return .failure(.workerCrashed) }
        do {
            return .success(try message.decode(as: Envelope<WorkerReply>.self).body)
        } catch let error as WorkerProtocolError {
            return .failure(error.jobError)
        } catch {
            return .failure(.internalInvariant("The app could not read the worker's reply."))
        }
    }
}

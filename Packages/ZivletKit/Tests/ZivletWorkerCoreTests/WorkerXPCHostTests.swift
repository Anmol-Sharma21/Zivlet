import Darwin
import EngineTestSupport
import Foundation
import Synchronization
import Testing
@preconcurrency import XPC
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@testable import ZivletWorkerCore

/// A raw XPC client of an anonymous worker listener in this process.
final class RawClient: @unchecked Sendable {
    let listener: XPCListener
    let session: XPCSession
    let events = EventLog()

    init(service: WorkerService) throws {
        listener = WorkerXPCHost.anonymous(service: service)
        let log = events
        session = try XPCSession(
            endpoint: listener.endpoint,
            incomingMessageHandler: { (message: XPCReceivedMessage) -> (any Encodable)? in
                if let event = try? message.decode(as: Envelope<WorkerEvent>.self) { log.sink(event.body) }
                return nil
            })
    }

    deinit {
        session.cancel(reason: "test done")
        listener.cancel()
    }

    func send<Body: Codable & Sendable & Equatable>(_ envelope: Envelope<Body>) async throws -> WorkerReply {
        let session = self.session
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(envelope) { (result: Result<XPCReceivedMessage, XPCRichError>) in
                    switch result {
                    case .success(let message):
                        continuation.resume(with: Result { try message.decode(as: Envelope<WorkerReply>.self).body })
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

@Suite("The worker's XPC glue over an anonymous listener (P2-01, R7)")
struct WorkerXPCHostTests {
    @Test func aPingCrossesRealXPC() async throws {
        let client = try RawClient(service: WorkerRig.service([ScriptedEngine()]))
        #expect(
            try await client.send(Envelope(WorkerRequest.ping)) == .pong(pid: getpid(), osBuild: WorkerService.osBuild))
    }

    /// Events are best-effort against the reply (XPC sends the reply on its own port), so they are awaited, but they
    /// keep their order among themselves.
    @Test func eventsCrossInOrder() async throws {
        let rig = try WorkerRig()
        let client = try RawClient(service: WorkerRig.service([ScriptedEngine(execution: .reportProgress)]))
        let (job, request) = try rig.executeRequest()
        let reply = try await client.send(Envelope(request))
        guard case .staged = reply else {
            Issue.record("not staged: \(reply)")
            return
        }
        for _ in 0..<500 where client.events.all.count < 2 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(
            client.events.all == [.progress(job, JobProgress(fraction: 0.5)), .progress(job, JobProgress(fraction: 1))])
    }

    @Test func anotherProtocolVersionIsAnsweredAsADamagedWorker() async throws {
        let client = try RawClient(service: WorkerRig.service([ScriptedEngine()]))
        let wrong = Envelope(protocolVersion: WorkerProtocol.version + 1, body: WorkerRequest.ping)
        #expect(try await client.send(wrong) == .failed(.engineDamaged(.worker)))
    }

    @Test func aCancelReachesARunningStep() async throws {
        let rig = try WorkerRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let client = try RawClient(service: WorkerRig.service([engine]))
        let (job, request) = try rig.executeRequest()
        async let reply = client.send(Envelope(request))
        await engine.reachedExecute.wait()
        #expect(try await client.send(Envelope(WorkerRequest.cancel(job))) == .accepted)
        #expect(try await reply == .failed(.cancelled))
    }

    @Test func requirementsMapToXPC() {
        _ = PeerRequirementSpec.sameTeam(identifier: "a").xpcRequirement
        _ = PeerRequirementSpec.signingIdentifier("a").xpcRequirement
    }
}

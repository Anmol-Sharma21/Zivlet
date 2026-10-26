import Foundation
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@Suite("Worker messages survive the wire (P2-01, 02 §7.5)")
struct IPCRoundTripTests {
    @Test(arguments: IPCFixtures.requests)
    func everyRequestSurvivesTheWire(_ request: WorkerRequest) throws {
        let data = try JSONEncoder().encode(Envelope(request))
        #expect(try Envelope<WorkerRequest>.decode(data).body == request)
    }

    @Test(arguments: IPCFixtures.replies)
    func everyReplySurvivesTheWire(_ reply: WorkerReply) throws {
        let data = try JSONEncoder().encode(Envelope(reply))
        #expect(try Envelope<WorkerReply>.decode(data).body == reply)
    }

    @Test(arguments: IPCFixtures.events)
    func everyEventSurvivesTheWire(_ event: WorkerEvent) throws {
        let data = try JSONEncoder().encode(Envelope(event))
        #expect(try Envelope<WorkerEvent>.decode(data).body == event)
    }

    @Test func anEnvelopeCarriesTheCurrentProtocolVersion() {
        #expect(Envelope(WorkerRequest.ping).protocolVersion == WorkerProtocol.version)
    }

    @Test func anotherProtocolVersionIsRefused() throws {
        let found = WorkerProtocol.version + 1
        let data = try JSONEncoder().encode(Envelope(protocolVersion: found, body: WorkerRequest.ping))
        #expect(throws: WorkerProtocolError.versionMismatch(expected: WorkerProtocol.version, found: found)) {
            try Envelope<WorkerRequest>.decode(data)
        }
    }

    @Test func aVersionMismatchIsReportedAsADamagedWorker() {
        let error = WorkerProtocolError.versionMismatch(expected: 1, found: 2)
        #expect(error.jobError == .engineDamaged(.worker))
    }

    @Test func capabilitiesAnswerHandlesAndAvailabilityPerEngine() throws {
        let image = try #require(IPCFixtures.capabilities.engine(.image))
        #expect(image.handles(ConversionPair(source: .png, target: .jpg)))
        #expect(!image.handles(ConversionPair(source: .mp3, target: .wav)))
        #expect(image.availability(of: ConversionPair(source: .png, target: .webp)) == .unavailable(["libwebp"]))
        #expect(image.availability(of: ConversionPair(source: .mp3, target: .wav)) == .unavailable([]))
        #expect(IPCFixtures.capabilities.engine(.media) == nil)
    }

    @Test func aWorkerEventNamesItsJob() {
        #expect(IPCFixtures.events.allSatisfy { $0.job == IPCFixtures.job })
    }
}

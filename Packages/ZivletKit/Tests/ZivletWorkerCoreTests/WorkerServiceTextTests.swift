import EngineVision
import Foundation
import Synchronization
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletIPC

@testable import ZivletWorkerCore

@Suite("Text jobs in the worker (P2-103, plan 18d D8): every Vision call runs here")
struct WorkerServiceTextTests {
    let dir: TempDir

    init() throws { dir = try TempDir(prefix: "zivlet-text-service") }

    func service(_ recognizer: ScriptedRecognizer) -> WorkerService {
        WorkerService(
            engines: [], text: TextReader(recognizer: recognizer, capabilities: { Self.capabilities }), onIdle: {})
    }

    static let capabilities = VisionCapabilities(languages: [.hindi, .english], osBuild: "26A1")

    @Test func aTextJobRepliesWithTheTextAndReportsProgressFirst() async throws {
        let job = TextJob(inputs: [try TextFiles.png("a.png", in: dir)], languages: [.english])
        let log = EventLog()
        let reply = await service(ScriptedRecognizer(["Hello there"])).handle(.recognizeText(job), events: log.sink)
        guard case .text(let text) = reply else {
            Issue.record("no text: \(reply)")
            return
        }
        #expect(text.text == "Hello there\n")
        #expect(log.all == [.progress(job.id, JobProgress(fraction: 1))])
    }

    @Test func aFailureComesBackAsATextError() async throws {
        let job = TextJob(inputs: [try dir.file("bad.png", "junk")], languages: [.english])
        let reply = await service(ScriptedRecognizer(["x"])).handle(.recognizeText(job), events: { _ in })
        #expect(reply == .textFailed(.unreadable))
    }

    @Test func cancelStopsARunningTextJob() async throws {
        let recognizer = ScriptedRecognizer(["x"], delay: .seconds(5))
        let service = service(recognizer)
        let job = TextJob(inputs: [try TextFiles.png("a.png", in: dir)], languages: [.english])
        async let reply = service.handle(.recognizeText(job), events: { _ in })
        for _ in 0..<500 where await service.runningJobs.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await service.handle(.cancel(job.id), events: { _ in }) == .accepted)
        #expect(await reply == .textFailed(.cancelled))
    }

    @Test func capabilitiesAndTheWarmUpAreAnswered() async throws {
        let recognizer = ScriptedRecognizer(["x"])
        let service = service(recognizer)
        #expect(await service.handle(.textCapabilities, events: { _ in }) == .textCapabilities(Self.capabilities))
        #expect(await service.handle(.warmUpText([.english]), events: { _ in }) == .accepted)
        #expect(recognizer.calls == 3)
    }

    @Test func aWorkerWithoutTextRefusesTextRequests() async throws {
        let service = WorkerService(engines: [], onIdle: {})
        let job = TextJob(inputs: [try TextFiles.png("a.png", in: dir)], languages: [.english])
        #expect(await service.handle(.recognizeText(job), events: { _ in }) == .failed(.engineMissing(.vision)))
    }
}

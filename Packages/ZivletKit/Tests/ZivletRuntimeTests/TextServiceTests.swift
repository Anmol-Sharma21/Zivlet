import EngineVision
import Foundation
import Synchronization
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

/// A text service whose worker is a loopback hosting a scripted recognizer.
struct TextRig {
    let dir: TempDir
    let recognizer: ScriptedRecognizer
    let transport: LoopbackTransport
    let service: TextService

    init(texts: [String] = ["Some text"], delay: Duration = .zero, crash: LoopbackTransport.CrashRule = .never)
        throws
    {
        dir = try TempDir(prefix: "zivlet-text-service")
        recognizer = ScriptedRecognizer(texts, delay: delay)
        let capabilities = VisionCapabilities(languages: [.hindi, .english], osBuild: "26A1")
        let worker = WorkerService(
            engines: [], text: TextReader(recognizer: recognizer, capabilities: { capabilities }), onIdle: {})
        transport = LoopbackTransport(service: worker, crash: crash)
        let bundle = try dir.folder("ZivletWorker.xpc")
        let selection = WorkerSelection(
            workerBundle: bundle, verify: { _ throws(JobError) in }, connection: WorkerConnection(transport: transport))
        service = TextService(selection: selection)
    }

    func png(_ name: String) throws -> URL { try TextFiles.png(name, in: dir) }
}

@Suite("Text service (P2-104, plan 18d D8): Copy Text runs in the worker, retried once after a crash")
struct TextServiceTests {
    @Test func twoImagesComeBackAsOneTextWithSeparators() async throws {
        let rig = try TextRig(texts: ["One", "Two"])
        let text = try await rig.service.copyText([try rig.png("a.png"), try rig.png("b.png")], languages: [.english])
        #expect(text.text == "— a.png —\nOne\n\n— b.png —\nTwo\n")
    }

    @Test func progressRunsFromTheWorkerToOne() async throws {
        let rig = try TextRig()
        let seen = Mutex<[Double]>([])
        let inputs = [try rig.png("a.png"), try rig.png("b.png")]
        _ = try await rig.service.copyText(inputs, languages: [.english]) { value in
            seen.withLock { $0.append(value) }
        }
        #expect(seen.withLock { $0 } == [0.5, 1.0])
    }

    @Test func cancellingTheTaskCancelsTheWorkersJob() async throws {
        let rig = try TextRig(delay: .seconds(5))
        let input = try rig.png("a.png")
        let task = Task { try await rig.service.copyText([input], languages: [.english]) }
        for _ in 0..<500 where rig.recognizer.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        let started = ContinuousClock.now
        task.cancel()
        await #expect(throws: TextError.cancelled) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test func aCrashIsRetriedOnceAndSucceeds() async throws {
        let rig = try TextRig(texts: ["Recovered"], crash: .onceWhenInputIs("a.png"))
        let text = try await rig.service.copyText([try rig.png("a.png")], languages: [.english])
        #expect(text.text == "Recovered\n")
        #expect(rig.transport.attempts(for: "a.png") == 2)
    }

    @Test func aSecondCrashNamesTheFile() async throws {
        let rig = try TextRig(crash: .whenInputIs("bad.png"))
        await #expect(throws: TextError.engineCrashedOnInput) {
            try await rig.service.copyText([try rig.png("bad.png")], languages: [.english])
        }
        #expect(rig.transport.attempts(for: "bad.png") == 2)
    }

    @Test func noWorkerMeansTextRecognitionIsUnavailable() async throws {
        let dir = try TempDir()
        let selection = WorkerSelection(
            workerBundle: dir.url.appending(path: "Missing.xpc"), verify: { _ throws(JobError) in },
            connection: WorkerConnection(transport: SilentTransport()))
        let input = try TextFiles.png("a.png", in: dir)
        await #expect(throws: TextError.unavailable) {
            try await TextService(selection: selection).copyText([input], languages: [.english])
        }
    }

    @Test func inputsAreCheckedInTheAppFirst() async throws {
        let rig = try TextRig()
        let folder = try rig.dir.folder("photos.png")
        await #expect(throws: TextError.unreadable) {
            try await rig.service.copyText([folder], languages: [.english])
        }
        await #expect(throws: TextError.unreadable) {
            try await rig.service.copyText([], languages: [.english])
        }
        let many = Array(repeating: folder, count: TextJob.maximumInputs + 1)
        await #expect(throws: TextError.tooManyFiles(limit: TextJob.maximumInputs)) {
            try await rig.service.copyText(many, languages: [.english])
        }
        #expect(rig.recognizer.calls == 0)
    }

    @Test func capabilitiesComeFromTheWorker() async throws {
        let rig = try TextRig()
        #expect(try await rig.service.capabilities().hasHindi)
    }

    @Test func theWarmUpRunsInTheWorker() async throws {
        let rig = try TextRig()
        try await rig.service.warmUp([.hindi, .english])
        #expect(rig.recognizer.calls == 3)
    }
}

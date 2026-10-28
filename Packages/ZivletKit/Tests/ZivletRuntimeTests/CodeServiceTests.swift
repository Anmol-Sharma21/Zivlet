import EngineVision
import Foundation
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

/// A code service whose worker is a loopback hosting a scripted detector.
struct CodeRig {
    let dir: TempDir
    let detector: ScriptedDetector
    let service: CodeService

    init(payloads: [String] = ["https://zivlet.app/test"], delay: Duration = .zero) throws {
        dir = try TempDir(prefix: "zivlet-code-service")
        detector = ScriptedDetector(payloads: payloads, delay: delay)
        let worker = WorkerService(engines: [], codes: CodeReading(reader: CodeReader(detector: detector)), onIdle: {})
        let transport = LoopbackTransport(service: worker)
        let bundle = try dir.folder("ZivletWorker.xpc")
        let selection = WorkerSelection(
            workerBundle: bundle, verify: { _ throws(JobError) in }, connection: WorkerConnection(transport: transport))
        service = CodeService(selection: selection)
    }

    func png(_ name: String) throws -> URL { try TextFiles.png(name, in: dir) }
}

@Suite("Code service (P2-51, plan 20b A8): Read QR runs in the worker, never in the app")
struct CodeServiceTests {
    @Test func theWorkerReadsTheCodesOfEachFile() async throws {
        let rig = try CodeRig(payloads: ["one", "two"])
        let files = try await rig.service.readCodes([try rig.png("a.png"), try rig.png("b.png")])
        #expect(files.map(\.name) == ["a.png", "b.png"])
        #expect(files.flatMap(\.codes).map(\.payload) == ["one", "two"])
    }

    @Test func cancellingTheTaskCancelsTheWorkersJob() async throws {
        let rig = try CodeRig(delay: .seconds(30))
        let input = try rig.png("a.png")
        let task = Task { try await rig.service.readCodes([input]) }
        for _ in 0..<2_000 where rig.detector.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        task.cancel()
        await #expect(throws: CodeError.cancelled) { try await task.value }
    }

    @Test func theAppChecksTheDropBeforeTheWorkerDoes() async throws {
        let rig = try CodeRig()
        await #expect(throws: CodeError.unreadable) { try await rig.service.readCodes([]) }
        await #expect(throws: CodeError.unreadable) { try await rig.service.readCodes([rig.dir.url]) }
        let many = Array(repeating: try rig.png("a.png"), count: CodeJob.maximumInputs + 1)
        await #expect(throws: CodeError.tooManyFiles(limit: CodeJob.maximumInputs)) {
            try await rig.service.readCodes(many)
        }
        #expect(rig.detector.calls == 0)
    }

    @Test func noWorkerMeansCodesCannotBeRead() async throws {
        let dir = try TempDir(prefix: "zivlet-code-service")
        let selection = WorkerSelection(
            workerBundle: dir.url.appending(path: "missing.xpc"), verify: { _ throws(JobError) in },
            connection: WorkerConnection(transport: LoopbackTransport(service: WorkerService(engines: [], onIdle: {}))))
        let service = CodeService(selection: selection)
        await #expect(throws: CodeError.unavailable) {
            try await service.readCodes([try TextFiles.png("a.png", in: dir)])
        }
    }

    @Test(arguments: [
        (JobError.cancelled, CodeError.cancelled), (.workerCrashed, .engineCrashedOnInput),
        (.engineMissing(.vision), .unavailable), (.unsupportedInput(.notAFile), .unreadable),
        (.internalInvariant("x"), .detectionFailed),
    ])
    func workerErrorsBecomeCodeErrors(job: JobError, code: CodeError) {
        #expect(CodeService.codeError(job) == code)
    }
}

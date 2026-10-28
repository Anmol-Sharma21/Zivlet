import EngineVision
import Foundation
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletIPC

@testable import ZivletWorkerCore

@Suite("Code jobs in the worker (P2-51, plan 20b A8): every Vision call runs here, one file's error stays its own")
struct WorkerServiceCodeTests {
    let dir: TempDir

    init() throws { dir = try TempDir(prefix: "zivlet-code-service") }

    func service(_ detector: ScriptedDetector) -> WorkerService {
        WorkerService(engines: [], codes: CodeReading(reader: CodeReader(detector: detector)), onIdle: {})
    }

    @Test func eachFileComesBackWithItsCodesAndProgressPerFile() async throws {
        let inputs = [try TextFiles.png("a.png", in: dir), try TextFiles.png("b.png", in: dir)]
        let job = CodeJob(inputs: inputs, pageLimit: 500)
        let log = EventLog()
        let reply = await service(ScriptedDetector(payloads: ["one", "two"])).handle(.readCodes(job), events: log.sink)
        #expect(
            reply
                == .codes([
                    FileCodes(name: "a.png", codes: [FoundCode(payload: "one", symbology: "qr", page: nil)]),
                    FileCodes(name: "b.png", codes: [FoundCode(payload: "two", symbology: "qr", page: nil)]),
                ]))
        #expect(
            log.all == [.progress(job.id, JobProgress(fraction: 0.5)), .progress(job.id, JobProgress(fraction: 1))])
    }

    @Test func aFileThatCannotBeReadIsNamedAndTheOthersAreRead() async throws {
        let inputs = [try dir.file("bad.png", "junk"), try TextFiles.png("good.png", in: dir)]
        let reply = await service(ScriptedDetector(payloads: ["fine"])).handle(
            .readCodes(CodeJob(inputs: inputs, pageLimit: 500)), events: { _ in })
        #expect(
            reply
                == .codes([
                    FileCodes(name: "bad.png", error: .unreadable),
                    FileCodes(name: "good.png", codes: [FoundCode(payload: "fine", symbology: "qr", page: nil)]),
                ]))
    }

    @Test func aCancelStopsTheJob() async throws {
        let detector = ScriptedDetector(payloads: ["slow"], delay: .seconds(30))
        let service = service(detector)
        let job = CodeJob(inputs: [try TextFiles.png("a.png", in: dir)], pageLimit: 500)
        let reply = Task { await service.handle(.readCodes(job), events: { _ in }) }
        for _ in 0..<2_000 where detector.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        _ = await service.handle(.cancel(job.id), events: { _ in })
        #expect(await reply.value == .codesFailed(.cancelled))
    }

    @Test func aWorkerWithoutVisionRefusesCodeJobs() async throws {
        let job = CodeJob(inputs: [try TextFiles.png("a.png", in: dir)], pageLimit: 500)
        let reply = await WorkerService(engines: [], onIdle: {}).handle(.readCodes(job), events: { _ in })
        #expect(reply == .failed(.engineMissing(.vision)))
    }
}

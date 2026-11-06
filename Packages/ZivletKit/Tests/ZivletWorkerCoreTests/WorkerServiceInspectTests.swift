import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@testable import ZivletWorkerCore

/// LOCK · UNLOCK asks the worker what each dropped PDF is before it asks for a password (plan 20f E3, E9).
@Suite("The worker inspects dropped PDFs without a password")
struct WorkerServiceInspectTests {
    struct FakeInspector: PDFInspecting {
        func preflight(_ file: URL) async -> Result<PDFPreflight, JobError> {
            file.lastPathComponent == "damaged.pdf"
                ? .failure(.unsupportedInput(.pdfDamaged)) : .success(PDFPreflight(pageCount: 3))
        }
    }

    @Test func eachFileGetsItsOwnAnswerInOrder() async throws {
        let dir = try TempDir(prefix: "zivlet-inspect")
        let files = [try dir.file("a.pdf", "%PDF"), try dir.file("damaged.pdf", "%PDF")]
        let service = WorkerService(engines: [], pdf: FakeInspector(), onIdle: {})
        let reply = await service.handle(.inspectPDFs(files), events: { _ in })
        #expect(reply == .inspected([.read(PDFPreflight(pageCount: 3)), .refused(.unsupportedInput(.pdfDamaged))]))
    }

    @Test func aWorkerWithoutAnInspectorSaysThePDFEngineIsMissing() async throws {
        let dir = try TempDir(prefix: "zivlet-inspect")
        let service = WorkerService(engines: [], onIdle: {})
        #expect(
            await service.handle(.inspectPDFs([try dir.file("a.pdf", "%PDF")]), events: { _ in })
                == .failed(.engineMissing(.pdf)))
    }
}

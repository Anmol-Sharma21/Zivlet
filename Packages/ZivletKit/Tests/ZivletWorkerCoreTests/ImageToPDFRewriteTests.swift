import CoreGraphics
import EngineImage
import EnginePDF
import EngineTestSupport
import Foundation
import ImageIO
import PDFKit
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletRuntime

@testable import ZivletWorkerCore

/// The qpdf-first rule on the one Quartz writer of M7 (plan 20e D4, D-PDF-3): in the worker, a JPEG → PDF output is
/// rewritten and checked by qpdf before it is published. The in-process fallback has no qpdf (D-M7-16), so its output
/// stays as Quartz wrote it.
@Suite("JPEG → PDF is rewritten by qpdf in the worker (D-PDF-3)")
struct ImageToPDFRewriteTests {
    /// The bytes qpdf writes on a PDF's second line; Quartz writes others.
    static let qpdfMarker = Data([0x25, 0xBF, 0xF7, 0xA2, 0xFE])

    struct Rig {
        let dir: TempDir
        let request: JobRequest
        let workspace: JobWorkspace

        init() throws {
            dir = try TempDir(prefix: "zivlet-rewrite")
            let input = dir.url.appending(path: "photo.jpg")
            try Self.writeJPEG(to: input)
            let id = JobID()
            let staged = try dir.folder(".zivlet-\(id)").appending(path: "staged.pdf")
            try Data().write(to: staged)
            let size = try FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int ?? 0
            let item = try InputItem(url: input, format: .jpg, byteCount: Int64(size))
            request = try JobRequest(id: id, input: item, operation: .convert(.pdf), destination: dir.url)
            workspace = JobWorkspace(job: id, stagedFile: staged)
        }

        /// A small grey JPEG, drawn here.
        private static func writeJPEG(to url: URL) throws {
            let context = try #require(
                CGContext(
                    data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            let image = try #require(context.makeImage())
            let destination = try #require(
                CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }

    @Test func aJPEGToPDFJobThroughTheLoopbackWorkerPublishesWhatQPDFWrote() async throws {
        let rig = try Rig()
        let service = WorkerRig.service([PDFRewritingEngine(wrapping: ImageEngine())])
        let connection = WorkerConnection(transport: LoopbackTransport(service: service))

        let plan = try await connection.prepare(rig.request, workspace: rig.workspace)
        let output = try await connection.execute(plan, job: rig.request.id, context: ExecutionContext())
        try await connection.verify(output, plan: plan)

        let bytes = try Data(contentsOf: output.url)
        #expect(bytes.range(of: Self.qpdfMarker) != nil)
        #expect(output.byteCount == Int64(bytes.count))
        #expect(PDFDocument(url: output.url)?.pageCount == 1)
        #expect(try QPDFDocumentReader.check(output.url, password: nil) == 0)
    }

    @Test func theInProcessPathKeepsWhatQuartzWrote() async throws {
        let rig = try Rig()
        let engine = ImageEngine()

        let plan = try await engine.prepare(rig.request, workspace: rig.workspace)
        let output = try await engine.execute(plan, context: ExecutionContext())
        try await engine.verify(output, plan: plan)

        let bytes = try Data(contentsOf: output.url)
        #expect(bytes.range(of: Self.qpdfMarker) == nil)
        #expect(String(decoding: bytes.prefix(5), as: UTF8.self) == "%PDF-")
        #expect(PDFDocument(url: output.url)?.pageCount == 1)
    }
}

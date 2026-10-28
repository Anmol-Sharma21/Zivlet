import CoreGraphics
import Foundation
import OCRTestSupport
import Synchronization
import TestSupport
import Testing

@testable import EngineVision

/// Records each image it is given and answers with the next canned list.
final class FakeDetector: BarcodeDetecting {
    private let answers: Mutex<[[DetectedCode]]>
    private let sizes = Mutex<[CGSize]>([])
    let failure: (any Error)?

    init(_ answers: [[DetectedCode]] = [], failure: (any Error)? = nil) {
        self.answers = Mutex(answers)
        self.failure = failure
    }

    var seen: [CGSize] { sizes.withLock { $0 } }

    func detect(_ image: CGImage) async throws -> [DetectedCode] {
        sizes.withLock { $0.append(CGSize(width: image.width, height: image.height)) }
        if let failure { throw failure }
        return answers.withLock { $0.isEmpty ? [] : $0.removeFirst() }
    }
}

struct DetectorBroke: Error {}

@Suite("Read QR (P2-51, plan 20b A7): codes from images and PDF pages, in page and reading order")
struct CodeReaderTests {
    static func code(_ payload: String, _ symbology: String = "qr", top: Double) -> DetectedCode {
        DetectedCode(payload: payload, symbology: symbology, top: top)
    }

    @Test func codesAreReadTopToBottomAndADuplicateOnOnePageIsKeptOnce() {
        let detected = [
            Self.code("lower", top: 0.2), Self.code("upper", top: 0.9), Self.code("upper", top: 0.5),
            Self.code("upper", "code128", top: 0.4),
        ]
        let found = FoundCode.arranged(detected, page: 3)
        #expect(found.map(\.payload) == ["upper", "upper", "lower"])
        #expect(found.map(\.symbology) == ["qr", "code128", "qr"])
        #expect(found.allSatisfy { $0.page == 3 })
    }

    @Test func anImageHasNoPageNumber() async throws {
        let dir = try TempDir()
        let url = try CodeFixtures.writePNG(try CodeFixtures.blank(), to: dir.url.appending(path: "a.png"))
        let reader = CodeReader(detector: FakeDetector([[Self.code("x", top: 0.5)]]))
        #expect(try await reader.read(url) == [FoundCode(payload: "x", symbology: "qr", page: nil)])
    }

    @Test func pdfPagesAreDrawnAt200DPIAndNumberedFromOne() async throws {
        let dir = try TempDir()
        let blank = try CodeFixtures.blank()
        let url = try CodeFixtures.writePDF([blank, blank], to: dir.url.appending(path: "two.pdf"))
        let detector = FakeDetector([[Self.code("one", top: 0.5)], [Self.code("two", top: 0.5)]])
        let found = try await CodeReader(detector: detector).read(url)
        #expect(found.map(\.page) == [1, 2] && found.map(\.payload) == ["one", "two"])
        #expect(detector.seen == Array(repeating: CGSize(width: 1700, height: 2200), count: 2))
    }

    @Test func aLockedPDFIsRefusedWithoutDrawingIt() async throws {
        let dir = try TempDir()
        let url = try CodeFixtures.writePDF(
            [try CodeFixtures.blank()], to: dir.url.appending(path: "locked.pdf"), userPassword: UUID().uuidString)
        let detector = FakeDetector()
        await #expect(throws: CodeError.pdfLocked) { try await CodeReader(detector: detector).read(url) }
        #expect(detector.seen.isEmpty)
    }

    @Test func morePagesThanTheLimitAreRefused() async throws {
        let dir = try TempDir()
        let blank = try CodeFixtures.blank()
        let url = try CodeFixtures.writePDF([blank, blank, blank], to: dir.url.appending(path: "three.pdf"))
        await #expect(throws: CodeError.tooManyPages(3)) {
            try await CodeReader(detector: FakeDetector()).read(url, pageLimit: 2)
        }
    }

    @Test func aFileThatIsNotAnImageOrAPDFIsUnreadable() async throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "notes.png")
        try Data("not an image".utf8).write(to: url)
        await #expect(throws: CodeError.unreadable) { try await CodeReader(detector: FakeDetector()).read(url) }
    }

    @Test func aDetectorFailureIsReportedWithoutItsDescriptionInTheLog() async throws {
        let dir = try TempDir()
        let url = try CodeFixtures.writePNG(try CodeFixtures.blank(), to: dir.url.appending(path: "a.png"))
        await #expect(throws: CodeError.detectionFailed) {
            try await CodeReader(detector: FakeDetector(failure: DetectorBroke())).read(url)
        }
        #expect(CodeError.detectionFailed.logDescription == "detectionFailed")
    }

    @Test func aCancelledReadStopsBeforeTheNextPage() async throws {
        let dir = try TempDir()
        let blank = try CodeFixtures.blank()
        let url = try CodeFixtures.writePDF([blank, blank], to: dir.url.appending(path: "two.pdf"))
        let detector = FakeDetector()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CodeReader(detector: detector).read(url)
        }
        await #expect(throws: CodeError.cancelled) { try await task.value }
        #expect(detector.seen.isEmpty)
    }

    @Test func errorsThatBelongToOneFileLetTheOthersGoOn() {
        #expect(CodeError.unreadable.isPerFile && CodeError.pdfLocked.isPerFile && CodeError.tooLarge.isPerFile)
        #expect(CodeError.tooManyPages(9).isPerFile && CodeError.detectionFailed.isPerFile)
        #expect(!CodeError.cancelled.isPerFile && !CodeError.unavailable.isPerFile)
        #expect(!CodeError.engineCrashedOnInput.isPerFile && !CodeError.tooManyFiles(limit: 500).isPerFile)
    }
}

/// Real Vision: opt-in with the OCR fixtures (`make ocr-check`), like M6's real-Vision tests (D-M6-13).
@Suite("Read QR through real Vision (plan 20b A7)", .enabled(if: OCRFixtures.realVisionEnabled))
struct CodeReaderVisionTests {
    @Test func everyPayloadIsReadBackExactly() async throws {
        let dir = try TempDir()
        let qr = try CodeFixtures.image(CodeFixtures.link)
        let barcode = try CodeFixtures.image(CodeFixtures.ticket, kind: .code128, scale: 4)
        let image = try CodeFixtures.stacked(qr, over: barcode)
        let url = try CodeFixtures.writePNG(image, to: dir.url.appending(path: "codes.png"))
        let found = try await CodeReader().read(url)
        #expect(found.map(\.payload) == [CodeFixtures.link, CodeFixtures.ticket])
        #expect(found.first?.symbology == "qr" && found.last?.symbology == "code128")
    }

    @Test func eachPageOfAPDFGivesItsCode() async throws {
        let dir = try TempDir()
        let pages = [try CodeFixtures.image(CodeFixtures.table), try CodeFixtures.image(CodeFixtures.link)]
        let url = try CodeFixtures.writePDF(pages, to: dir.url.appending(path: "two.pdf"))
        let found = try await CodeReader().read(url)
        #expect(found.map(\.payload) == [CodeFixtures.table, CodeFixtures.link] && found.map(\.page) == [1, 2])
    }

    @Test func aBlankImageHasNoCodes() async throws {
        let dir = try TempDir()
        let url = try CodeFixtures.writePNG(try CodeFixtures.blank(), to: dir.url.appending(path: "blank.png"))
        #expect(try await CodeReader().read(url).isEmpty)
    }
}

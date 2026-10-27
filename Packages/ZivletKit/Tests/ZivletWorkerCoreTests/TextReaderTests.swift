import EngineVision
import Foundation
import OCRTestSupport
import Synchronization
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletIPC

@testable import ZivletWorkerCore

@Suite("The worker's text reader (P2-104, plan 18d D8): images and PDFs into one text")
struct TextReaderTests {
    let dir: TempDir

    init() throws { dir = try TempDir(prefix: "zivlet-text") }

    @Test func twoImagesBecomeOneTextWithSeparators() async throws {
        let reader = TextReader(recognizer: ScriptedRecognizer(["First text", "दूसरा पाठ"]))
        let job = TextJob(
            inputs: [try TextFiles.png("a.png", in: dir), try TextFiles.png("b.png", in: dir)], languages: [.hindi])
        let text = try await reader.read(job) { _ in }
        #expect(text.text == "— a.png —\nFirst text\n\n— b.png —\nदूसरा पाठ\n")
        #expect(text.scripts == [.latin, .devanagari])
    }

    @Test func progressRunsToOneAcrossFiles() async throws {
        let reader = TextReader(recognizer: ScriptedRecognizer(["x"]))
        let inputs = try ["a.png", "b.png", "c.png", "d.png"].map { try TextFiles.png($0, in: dir) }
        let seen = Mutex<[Double]>([])
        _ = try await reader.read(TextJob(inputs: inputs, languages: [.english])) { value in
            seen.withLock { $0.append(value) }
        }
        #expect(seen.withLock { $0 } == [0.25, 0.5, 0.75, 1.0])
    }

    @Test func aPDFIsReadPageByPageWithinItsShare() async throws {
        let pdf = try PDFFixtures.renderScans(count: 2, into: dir.url)
        let recognizer = ScriptedRecognizer(["page"])
        let seen = Mutex<[Double]>([])
        let text = try await TextReader(recognizer: recognizer).read(
            TextJob(inputs: [try TextFiles.png("a.png", in: dir), pdf], languages: [.english])
        ) { value in seen.withLock { $0.append(value) } }
        #expect(recognizer.calls == 3)
        #expect(seen.withLock { $0 } == [0.5, 0.75, 1.0])
        #expect(text.perFile.map(\.name) == ["a.png", "scans.pdf"])
    }

    @Test func aHeaderAboveTheDecodeLimitIsRefusedBeforeVision() async throws {
        let recognizer = ScriptedRecognizer(["x"])
        let reader = TextReader(recognizer: recognizer, maximumPixels: 500)
        let image = try TextFiles.png("big.png", in: dir, width: 32, height: 24)
        let text = try await reader.read(TextJob(inputs: [image], languages: [.english])) { _ in }
        #expect(text.skipped == [SkippedFile(name: "big.png", error: .tooLarge)])
        #expect(recognizer.calls == 0)
    }

    @Test func aFortyThousandPixelSquareHeaderNeverReachesVision() async throws {
        let recognizer = ScriptedRecognizer(["x"])
        let huge = try TextFiles.pngHeader("huge.png", in: dir, width: 40_000, height: 40_000)
        let text = try await TextReader(recognizer: recognizer).read(TextJob(inputs: [huge], languages: [.english])) {
            _ in
        }
        #expect(text.skipped.count == 1 && text.isEmpty)
        #expect(recognizer.calls == 0)
    }

    @Test func aFileThatIsNeitherImageNorPDFIsUnreadable() async throws {
        let junk = try dir.file("notes.png", "not an image")
        let text = try await TextReader(recognizer: ScriptedRecognizer(["x"])).read(
            TextJob(inputs: [junk], languages: [.english])
        ) { _ in }
        #expect(text.skipped == [SkippedFile(name: "notes.png", error: .unreadable)])
    }

    @Test func aLargeImageIsDecodedNoBiggerThanTheCap() async throws {
        let recognizer = ScriptedRecognizer(["x"])
        let wide = try TextFiles.png("wide.png", in: dir, width: 9000, height: 10)
        _ = try await TextReader(recognizer: recognizer).read(TextJob(inputs: [wide], languages: [.english])) { _ in }
        #expect(recognizer.sizes.withLock { $0.first?.width } == 8192)
    }

    /// One unreadable file of a drop does not throw away the text of the others (minutes of OCR, perhaps).
    @Test func aFileThatCannotBeReadIsSkippedAndTheOthersAreKept() async throws {
        let reader = TextReader(recognizer: ScriptedRecognizer(["First text", "Third text"]))
        let inputs = [
            try TextFiles.png("a.png", in: dir), try dir.file("bad.png", "junk"), try TextFiles.png("c.png", in: dir),
        ]
        let seen = Mutex<[Double]>([])
        let text = try await reader.read(TextJob(inputs: inputs, languages: [.english])) { value in
            seen.withLock { $0.append(value) }
        }
        #expect(text.text == "— a.png —\nFirst text\n\n— c.png —\nThird text\n")
        #expect(text.skipped == [SkippedFile(name: "bad.png", error: .unreadable)])
        #expect(text.perFile.map(\.name) == ["a.png", "bad.png", "c.png"])  // still one entry per input, in order
        #expect(seen.withLock { $0.last } == 1)
    }

    @Test func aCancelStillStopsTheWholeJob() async throws {
        let recognizer = ScriptedRecognizer(["x"], delay: .seconds(5))
        let inputs = [try TextFiles.png("a.png", in: dir), try TextFiles.png("b.png", in: dir)]
        let reader = TextReader(recognizer: recognizer)
        let task = Task { try await reader.read(TextJob(inputs: inputs, languages: [.english])) { _ in } }
        for _ in 0..<500 where recognizer.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        task.cancel()
        await #expect(throws: TextError.cancelled) { try await task.value }
    }

    /// A photo is decoded within an area cap as well as the side cap, as a rendered PDF page is, so one large photo
    /// does not hold hundreds of MB in the worker.
    @Test func aLargePhotoIsDecodedWithinTheAreaCap() async throws {
        let recognizer = ScriptedRecognizer(["x"])
        let photo = try TextFiles.png("photo.png", in: dir, width: 5_200, height: 5_000)
        _ = try await TextReader(recognizer: recognizer).read(TextJob(inputs: [photo], languages: [.english])) { _ in }
        let size = try #require(recognizer.sizes.withLock { $0.first })
        #expect(Int(size.width * size.height) <= 25_000_000)
        #expect(size.width > 4_000)  // scaled to the cap, not far below it
    }

    @Test func theDecodeSideKeepsSmallImagesAndCapsLargeOnes() {
        #expect(ImageTextSource.decodeSide(width: 640, height: 480) == 640)
        #expect(ImageTextSource.decodeSide(width: 9_000, height: 10) == 8_192)
        let side = ImageTextSource.decodeSide(width: 8_000, height: 8_000)
        #expect(side * side <= ImageTextSource.maximumDecodePixels && side >= 4_990)
    }

    @Test func theWarmUpReadsThreeImages() async throws {
        let recognizer = ScriptedRecognizer(["x"])
        try await TextReader(recognizer: recognizer).warmUp([.hindi, .english])
        #expect(recognizer.calls == 3)
    }
}

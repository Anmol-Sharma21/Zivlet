import CoreGraphics
import EngineVision
import Synchronization
import Testing

/// A Vision stand-in: records every call and its options, answers from a script.
final class FakeOCR: VisionOCR {
    enum Answer: Sendable {
        case text(String)
        case fail(String)
    }

    let documentsAnswer: Answer
    let accurateAnswer: Answer
    let calls = Mutex<[(kind: String, options: OCROptions)]>([])

    init(documents: Answer = .text("doc"), accurate: Answer = .text("lines")) {
        documentsAnswer = documents
        accurateAnswer = accurate
    }

    func documentText(_ image: CGImage, options: OCROptions) async throws -> String {
        try answer(documentsAnswer, kind: "documents", options: options)
    }

    func accurateText(_ image: CGImage, options: OCROptions) async throws -> String {
        try answer(accurateAnswer, kind: "accurate", options: options)
    }

    var kinds: [String] { calls.withLock { $0.map(\.kind) } }

    private func answer(_ answer: Answer, kind: String, options: OCROptions) throws -> String {
        calls.withLock { $0.append((kind, options)) }
        switch answer {
        case .text(let text): return text
        case .fail(let reason): throw FakeVisionError(reason: reason)
        }
    }
}

struct FakeVisionError: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

/// A 4 × 4 white image; the fake never looks at it.
func blankImage(width: Int = 4, height: Int = 4) throws -> CGImage {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

@Suite("Text recognizer (P2-103): documents request, ordered languages, one accurate fallback")
struct TextRecognizerTests {
    @Test func languagesPassThroughInOrderWithAutoDetectOff() async throws {
        let ocr = FakeOCR()
        let page = try await VisionTextRecognizer(ocr: ocr).recognize(try blankImage(), languages: [.hindi, .english])
        #expect(page.text == "doc")
        let options = try #require(ocr.calls.withLock { $0.first?.options })
        #expect(options.languages == [.hindi, .english])
        #expect(!options.automaticallyDetectLanguage)
        #expect(options.useLanguageCorrection)
        #expect(ocr.kinds == ["documents"])
    }

    @Test func aDocumentsFailureFallsBackOnceToTheAccurateRequest() async throws {
        let ocr = FakeOCR(documents: .fail("no documents"), accurate: .text("ok"))
        let page = try await VisionTextRecognizer(ocr: ocr).recognize(try blankImage(), languages: [.english])
        #expect(page.text == "ok")
        #expect(ocr.kinds == ["documents", "accurate"])
    }

    @Test func whenBothFailTheFallbacksErrorIsReturned() async throws {
        let ocr = FakeOCR(documents: .fail("first"), accurate: .fail("second"))
        await #expect(throws: TextError.recognitionFailed("second")) {
            try await VisionTextRecognizer(ocr: ocr).recognize(try blankImage(), languages: [.english])
        }
        #expect(ocr.kinds == ["documents", "accurate"])
    }

    @Test func aCancelledTaskNeverCallsVision() async throws {
        let ocr = FakeOCR()
        let image = try blankImage()
        let task = Task {
            try? await Task.sleep(for: .seconds(5))
            return try await VisionTextRecognizer(ocr: ocr).recognize(image, languages: [.english])
        }
        task.cancel()
        await #expect(throws: TextError.cancelled) { try await task.value }
        #expect(ocr.kinds.isEmpty)
    }

    @Test func scriptsAreDerivedFromTheText() {
        #expect(RecognizedPage(text: "Train का टिकट 4").scripts == [.latin, .devanagari])
        #expect(RecognizedPage(text: "आज").scripts == [.devanagari])
        #expect(RecognizedPage(text: "Hello, 42!").scripts == [.latin])
        #expect(RecognizedPage(text: "Привет").scripts == [.other])
        #expect(RecognizedPage(text: "  12 ₹ ").scripts.isEmpty)
        #expect(RecognizedPage(text: "").isEmpty)
        #expect(!RecognizedPage(text: "x").isEmpty)
    }
}

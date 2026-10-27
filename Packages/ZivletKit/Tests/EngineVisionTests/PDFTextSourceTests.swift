import CoreGraphics
import EngineVision
import Foundation
import OCRTestSupport
import Synchronization
import TestSupport
import Testing

/// Records the size of every image it is given and answers with a fixed text.
final class RecordingRecognizer: TextRecognizing {
    let answer: String
    let sizes = Mutex<[CGSize]>([])

    init(answer: String = "ocr text") { self.answer = answer }

    var calls: Int { sizes.withLock { $0.count } }

    func recognize(_ image: CGImage, languages: [LanguageTag]) async throws(TextError) -> RecognizedPage {
        sizes.withLock { $0.append(CGSize(width: image.width, height: image.height)) }
        return RecognizedPage(text: answer)
    }
}

@Suite("PDF text (P2-104, D-M6-15): the text layer when it is usable and not Devanagari, else OCR")
struct PDFTextSourceTests {
    let folder: TempDir

    init() throws { folder = try TempDir() }

    func read(_ url: URL, _ recognizer: RecordingRecognizer, progress: @escaping @Sendable (Double) -> Void = { _ in })
        async throws(TextError) -> [RecognizedPage]
    {
        try await PDFTextSource.read(url, recognizer: recognizer, languages: [.hindi, .english], progress: progress)
    }

    @Test func anEnglishTextLayerIsUsedWithoutOCR() async throws {
        let recognizer = RecordingRecognizer()
        let pages = try await read(try PDFFixtures.render(.english, into: folder.url), recognizer)
        #expect(recognizer.calls == 0)
        #expect(CharacterErrorRate.cer(reference: try PDFFixtures.text(of: .english), hypothesis: pages[0].text) == 0)
    }

    @Test(arguments: [PDFFixtures.Kind.hindi, .mixed])
    func aDevanagariTextLayerGoesToOCR(_ kind: PDFFixtures.Kind) async throws {
        let recognizer = RecordingRecognizer()
        let pages = try await read(try PDFFixtures.render(kind, into: folder.url), recognizer)
        #expect(recognizer.calls == 1)
        #expect(pages.map(\.text) == ["ocr text"])
    }

    @Test func aWebKitHindiPDFGoesToOCR() async throws {
        let url = try await PDFFixtures.renderWebKit(into: folder.url)
        let recognizer = RecordingRecognizer()
        _ = try await read(url, recognizer)
        #expect(recognizer.calls == 1)
    }

    @Test func aScanGoesToOCRAt300DPI() async throws {
        let recognizer = RecordingRecognizer()
        _ = try await read(try PDFFixtures.render(.scan, into: folder.url), recognizer)
        #expect(recognizer.sizes.withLock { $0 } == [CGSize(width: 2550, height: 3300)])
    }

    @Test func aFileThatDisallowsCopyingIsRefused() async throws {
        let url = try PDFFixtures.render(.noCopy, into: folder.url)
        await #expect(throws: TextError.copyingNotAllowed) { try await read(url, RecordingRecognizer()) }
    }

    @Test func aFileThatIsNotAPDFIsUnreadable() async throws {
        let url = try folder.file("fake.pdf", "not a pdf")
        await #expect(throws: TextError.unreadable) { try await read(url, RecordingRecognizer()) }
    }

    @Test func cancellingAfterPageTwoOfFiveStopsThere() async throws {
        let url = try PDFFixtures.renderScans(count: 5, into: folder.url)
        let recognizer = RecordingRecognizer()
        await #expect(throws: TextError.cancelled) {
            try await read(url, recognizer) { fraction in
                if fraction >= 0.4 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        #expect(recognizer.calls == 2)
    }

    @Test func progressRunsFromAFifthToOne() async throws {
        let url = try PDFFixtures.renderScans(count: 5, into: folder.url)
        let seen = Mutex<[Double]>([])
        _ = try await read(url, RecordingRecognizer()) { fraction in seen.withLock { $0.append(fraction) } }
        #expect(seen.withLock { $0 } == [0.2, 0.4, 0.6, 0.8, 1.0])
    }

    @Test func tooManyPagesAreRefusedBeforeAnyWork() async throws {
        let url = try PDFFixtures.renderScans(count: 3, into: folder.url)
        let recognizer = RecordingRecognizer()
        await #expect(throws: TextError.tooManyPages(3)) {
            try await PDFTextSource.read(
                url, recognizer: recognizer, languages: [.english], pageLimit: 2, progress: { _ in })
        }
        #expect(recognizer.calls == 0)
    }

    @Test func aLayerWithCarriageReturnsComesBackWithLineFeeds() {
        #expect(PDFTextSource.normalizedLayer("one\r\ntwo\rthree") == "one\ntwo\nthree")
    }
}

@Suite("Usable text (17a §3.8): at least 20 printable characters and under 5 % replacement characters")
struct UsableTextTests {
    @Test func shortTextIsNotUsable() {
        #expect(!UsableText.isUsable("short"))
        #expect(!UsableText.isUsable(String(repeating: " ", count: 40)))
    }

    @Test func enoughPrintableTextIsUsable() {
        #expect(UsableText.isUsable("The quarterly report is due on Friday."))
    }

    @Test func replacementCharactersMakeItUnusable() {
        let damaged = String(repeating: "a", count: 19) + "\u{FFFD}"
        #expect(!UsableText.isUsable(damaged))
        let mostlyFine = String(repeating: "a", count: 40) + "\u{FFFD}"
        #expect(UsableText.isUsable(mostlyFine))
    }
}

@Suite("Page renderer (plan 18d D5): crop box at 300 DPI, white behind, rotation honoured, capped")
struct PageRendererTests {
    @Test func theLongestSideAndThePixelCountAreCapped() {
        let letter = CGSize(width: 612, height: 792)
        #expect(PageRenderer.pixelSize(points: letter, dpi: 300) == CGSize(width: 2550, height: 3300))
        let poster = PageRenderer.pixelSize(points: CGSize(width: 2448, height: 3168), dpi: 300)
        #expect(poster.width <= 8192 && poster.height <= 8192)
        #expect(poster.width * poster.height <= 16_000_000)
        let strip = PageRenderer.pixelSize(points: CGSize(width: 10_000, height: 100), dpi: 300)
        #expect(strip.width == 8192)
    }
}

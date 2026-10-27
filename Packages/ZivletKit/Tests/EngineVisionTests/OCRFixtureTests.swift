import EngineVision
import Foundation
import OCRTestSupport
import TestSupport
import Testing

/// Exit row Z6 (`make ocr-check`): the 12 fixtures through real Vision with the production configuration. Opt-in,
/// because the first call compiles a model for minutes (D-M6-13). Runs serialised so each time is its own.
@Suite("OCR fixtures through Vision (Z6)", .serialized, .enabled(if: OCRFixtures.realVisionEnabled))
struct OCRFixtureTests {
    static let production: [LanguageTag] = [.hindi, .english]

    @Test(arguments: OCRFixtures.entries)
    func everyFixtureIsReadWithinOnePercent(_ entry: OCRFixtures.Entry) async throws {
        let image = try OCRFixtures.image(for: entry)
        let start = ContinuousClock.now
        let page = try await VisionTextRecognizer().recognize(image, languages: Self.production)
        let elapsed = ContinuousClock.now - start
        let cer = CharacterErrorRate.cer(reference: entry.text, hypothesis: page.text)
        OCRFixtures.log(
            "\(entry.name) cer=\(Self.format(cer)) ms=\(elapsed.milliseconds) text=\(Self.oneLine(page.text))")
        #expect(cer <= 0.01, "\(entry.name): \(page.text)")
        if Devanagari.contains(entry.text) {
            #expect(Devanagari.contains(page.text), "\(entry.name) lost its Devanagari")
        }
    }

    /// The language-order trap (17c §1.4): English alone loses the Devanagari. Printed, not scored.
    @Test func englishAloneIsPrintedForTheRecord() async throws {
        var lost: [String] = []
        for entry in OCRFixtures.entries where Devanagari.contains(entry.text) {
            let page = try await VisionTextRecognizer().recognize(OCRFixtures.image(for: entry), languages: [.english])
            if !Devanagari.contains(page.text) { lost.append(entry.name) }
        }
        OCRFixtures.log("English only: Devanagari lost in \(lost.count) fixtures: \(lost.joined(separator: " "))")
    }

    /// The unscored stress set: fixture 07's sentence at harder noise and smaller sizes (plan 18d).
    @Test func theStressSetIsPrintedNeverScored() async throws {
        let base = try #require(OCRFixtures.entries.first { $0.style == .degraded })
        for size in [16, 22, base.size] {
            for noise in [0.10, 0.20, 0.30, 0.45] {
                let entry = OCRFixtures.Entry(
                    name: "stress", font: base.font, fallback: base.fallback, size: size, style: .degraded,
                    lines: base.lines)
                let image = try OCRFixtures.image(for: entry, degradation: .fixture.with(noise: noise))
                let page = try await VisionTextRecognizer().recognize(image, languages: Self.production)
                let cer = CharacterErrorRate.cer(reference: entry.text, hypothesis: page.text)
                OCRFixtures.log("stress size=\(size) noise=\(Int(noise * 100))% cer=\(Self.format(cer))")
            }
        }
    }

    /// The PDF fixtures with real Vision: the English layer is read as is, the rest through OCR.
    @Test(arguments: [PDFFixtures.Kind.english, .hindi, .mixed, .scan])
    func everyPDFFixtureIsReadWithinOnePercent(_ kind: PDFFixtures.Kind) async throws {
        let folder = try TempDir()
        let url = try PDFFixtures.render(kind, into: folder.url)
        try await Self.check(url, truth: try PDFFixtures.text(of: kind), name: kind.rawValue)
    }

    @Test func theWebKitPDFIsReadWithinOnePercent() async throws {
        let folder = try TempDir()
        let url = try await PDFFixtures.renderWebKit(into: folder.url)
        try await Self.check(url, truth: try PDFFixtures.text(of: .hindi), name: "webkit")
    }

    /// OS-M6-3: the owner's private PDFs in `ZIVLET_OCR_PDFS`, printed with their CER against `<name>.txt` when it
    /// exists; no threshold, the owner judges.
    @Test func theOwnersPDFsArePrinted() async throws {
        guard let folder = ProcessInfo.processInfo.environment["ZIVLET_OCR_PDFS"], !folder.isEmpty else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".pdf") }.sorted()
        for file in files {
            let url = URL(fileURLWithPath: folder).appending(path: file)
            let pages = try await PDFTextSource.read(
                url, recognizer: VisionTextRecognizer(), languages: Self.production, progress: { _ in })
            let text = pages.map(\.text).joined(separator: "\n")
            let sidecar = url.deletingPathExtension().appendingPathExtension("txt")
            let truth = try? String(contentsOf: sidecar, encoding: .utf8)
            let score = truth.map { Self.format(CharacterErrorRate.cer(reference: $0, hypothesis: text)) } ?? "no truth"
            OCRFixtures.log("owner \(file) pages=\(pages.count) cer=\(score) chars=\(text.count)")
        }
    }

    static func check(_ url: URL, truth: String, name: String) async throws {
        let start = ContinuousClock.now
        let pages = try await PDFTextSource.read(
            url, recognizer: VisionTextRecognizer(), languages: production, progress: { _ in })
        let text = pages.map(\.text).joined(separator: "\n")
        let cer = CharacterErrorRate.cer(reference: truth, hypothesis: text)
        let ms = (ContinuousClock.now - start).milliseconds
        OCRFixtures.log("pdf \(name) cer=\(format(cer)) ms=\(ms) text=\(oneLine(text))")
        #expect(cer <= 0.01, "\(name): \(text)")
    }

    static func format(_ value: Double) -> String { String(format: "%.3f", value) }

    static func oneLine(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: " / ") }
}

extension Duration {
    var milliseconds: Int64 { components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000 }
}

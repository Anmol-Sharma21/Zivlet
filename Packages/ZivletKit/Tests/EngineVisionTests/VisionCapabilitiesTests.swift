import EngineVision
import Foundation
import OCRTestSupport
import Synchronization
import Testing
import ZivletCore

/// A language list without Vision; counts how often it was read.
final class FakeLanguageSource: VisionLanguageSource {
    let identifiers: [String]
    let reads = Mutex(0)

    init(_ identifiers: [String]) { self.identifiers = identifiers }

    func supportedLanguages() -> [LanguageTag] {
        reads.withLock { $0 += 1 }
        return identifiers.map { LanguageTag(locale: Locale.Language(identifier: $0)) }
    }
}

@Suite("Vision capabilities (P2-103, OWN-OCR-1): Hindi only where Vision lists it")
struct VisionCapabilitiesTests {
    @Test func hindiIsPresentWhenALanguageHasItsCode() {
        let capabilities = VisionCapabilities.probe(
            source: FakeLanguageSource(["en-Latn-US", "hi-Deva-IN", "mr-Deva-IN"]), osBuild: "26A1")
        #expect(capabilities.hasHindi)
        #expect(capabilities.languages.contains(LanguageTag(code: "hi", script: "Deva")))
        #expect(capabilities.osBuild == "26A1")
    }

    @Test func withoutHindiTheDefaultsDropIt() {
        let capabilities = VisionCapabilities.probe(source: FakeLanguageSource(["en-US", "fr-FR"]), osBuild: "26A1")
        #expect(!capabilities.hasHindi)
        let languages = RecognitionLanguages.defaults(
            preferred: ["hi-IN"], inputSources: [], choice: .hindiAndEnglish, capabilities: capabilities)
        #expect(languages == [.english])
    }

    @Test func withHindiTheDefaultsKeepIt() {
        let capabilities = VisionCapabilities.probe(source: FakeLanguageSource(["hi-Deva-IN"]), osBuild: "x")
        let languages = RecognitionLanguages.defaults(
            preferred: ["hi-IN"], inputSources: [], choice: .matchMine, capabilities: capabilities)
        #expect(languages == [.hindi, .english])
    }

    @Test func theProbeReadsTheSourceOnce() {
        let source = FakeLanguageSource(["hi-Deva-IN"])
        _ = VisionCapabilities.probe(source: source, osBuild: "x")
        #expect(source.reads.withLock { $0 } == 1)
    }

    @Test func capabilitiesSurviveACodableRoundTrip() throws {
        let capabilities = VisionCapabilities(languages: [.hindi, .english], osBuild: "26A1")
        let data = try JSONEncoder().encode(capabilities)
        #expect(try JSONDecoder().decode(VisionCapabilities.self, from: data) == capabilities)
    }

    @Test func aLocaleWithoutAScriptGetsAnEmptyOne() {
        #expect(LanguageTag(locale: Locale.Language(identifier: "en")).code == "en")
    }

    /// Opt-in (make ocr-check): the real list on this Mac; reading it compiles no model.
    @Test(.enabled(if: OCRFixtures.realVisionEnabled))
    func theRealSourceListsHindiAndMarathi() {
        let capabilities = VisionCapabilities.current
        OCRFixtures.log("Vision languages: \(capabilities.languages.map(\.identifier).joined(separator: " "))")
        #expect(capabilities.hasHindi)
        #expect(capabilities.languages.contains { $0.code == "mr" })
    }
}

import Foundation
import Vision
import ZivletCore
import ZivletEngineKit

/// Where the recognition languages come from: Vision in production, a list in tests.
public protocol VisionLanguageSource: Sendable {
    func supportedLanguages() -> [LanguageTag]
}

/// The documents request's own list (the accurate text request supports the same set, plan 18 §3.2). Reading it
/// compiles no model.
public struct VisionDocumentLanguages: VisionLanguageSource {
    public init() {}

    public func supportedLanguages() -> [LanguageTag] {
        RecognizeDocumentsRequest().supportedRecognitionLanguages.map(LanguageTag.init(locale:))
    }
}

/// What this Mac's Vision can read (P2-103, OWN-OCR-1). Hindi counts as present when any language has the code `hi`
/// (the Swift API reports `hi-Deva-IN`). Codable so the worker can report it to the app.
public struct VisionCapabilities: Codable, Sendable, Equatable {
    public let languages: [LanguageTag]
    public let osBuild: String

    public init(languages: [LanguageTag], osBuild: String) {
        self.languages = languages
        self.osBuild = osBuild
    }

    public var hasHindi: Bool { languages.contains { $0.code == LanguageTag.hindi.code } }

    public static func probe(source: any VisionLanguageSource, osBuild: String = CapabilityProbe.currentOSBuild())
        -> VisionCapabilities
    {
        VisionCapabilities(languages: source.supportedLanguages(), osBuild: osBuild)
    }

    /// Probed once per process, at first use.
    public static let current = probe(source: VisionDocumentLanguages())
}

extension LanguageTag {
    public init(locale: Locale.Language) {
        self.init(code: locale.languageCode?.identifier ?? "", script: locale.script?.identifier ?? "")
    }
}

extension RecognitionLanguages {
    public static func defaults(
        preferred: [String], inputSources: [String], choice: TextLanguageChoice, capabilities: VisionCapabilities
    ) -> [LanguageTag] {
        defaults(
            preferred: preferred, inputSources: inputSources, choice: choice, hindiAvailable: capabilities.hasHindi)
    }

    /// The choice would read Hindi, but this Mac's Vision has none, so the job reads English only.
    public static func skipsHindi(
        preferred: [String], inputSources: [String], choice: TextLanguageChoice, capabilities: VisionCapabilities
    ) -> Bool {
        !capabilities.hasHindi
            && defaults(preferred: preferred, inputSources: inputSources, choice: choice, hindiAvailable: true)
                .contains(.hindi)
    }
}

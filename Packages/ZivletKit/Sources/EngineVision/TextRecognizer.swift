import CoreGraphics
import os

/// Reads the text of one image (P2-103). Production: `VisionTextRecognizer`, run only in the worker (D-M6-8).
public protocol TextRecognizing: Sendable {
    func recognize(_ image: CGImage, languages: [LanguageTag]) async throws(TextError) -> RecognizedPage
}

/// The options every recognition uses: the languages in order, automatic detection off, language correction on.
public struct OCROptions: Sendable, Equatable {
    public let languages: [LanguageTag]
    public let automaticallyDetectLanguage: Bool
    public let useLanguageCorrection: Bool

    public init(languages: [LanguageTag]) {
        self.languages = languages
        automaticallyDetectLanguage = false
        useLanguageCorrection = true
    }
}

/// The two Vision requests behind a port, so the recognizer's rules are tested without Vision.
public protocol VisionOCR: Sendable {
    /// `RecognizeDocumentsRequest`: paragraphs joined by line breaks, tables as tab-separated rows.
    func documentText(_ image: CGImage, options: OCROptions) async throws -> String
    /// `RecognizeTextRequest` at `.accurate`: lines joined by line breaks.
    func accurateText(_ image: CGImage, options: OCROptions) async throws -> String
}

/// The documents request first; if it throws, or finds only white space, one fallback to the accurate text request
/// with the same languages (P2-103's [challenge]): an empty documents result is not trusted as "no text". Both empty
/// is no text, not an error. Vision calls cannot be interrupted, so cancellation is checked before each request and
/// after it returns.
public struct VisionTextRecognizer: TextRecognizing {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    let ocr: any VisionOCR

    public init(ocr: any VisionOCR = VisionFrameworkOCR()) {
        self.ocr = ocr
    }

    public func recognize(_ image: CGImage, languages: [LanguageTag]) async throws(TextError) -> RecognizedPage {
        let options = OCROptions(languages: languages)
        try Self.checkCancelled()
        var documentsFailed = false
        do {
            let text = try await ocr.documentText(image, options: options)
            try Self.checkCancelled()
            if !Self.isBlank(text) { return RecognizedPage(text: text) }
        } catch {
            try Self.checkCancelled()
            documentsFailed = true
            // The error's type only: Vision's description may name a file (NFR-6).
            Self.logger.notice("Documents request failed (\(String(describing: type(of: error)), privacy: .public))")
        }
        do {
            let text = try await ocr.accurateText(image, options: options)
            try Self.checkCancelled()
            return RecognizedPage(text: text)
        } catch {
            try Self.checkCancelled()
            guard documentsFailed else { return RecognizedPage(text: "") }
            throw .recognitionFailed(String(describing: error))
        }
    }

    static func isBlank(_ text: String) -> Bool { text.allSatisfy(\.isWhitespace) }

    static func checkCancelled() throws(TextError) {
        if Task.isCancelled { throw .cancelled }
    }
}

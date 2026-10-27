import CoreGraphics
import Vision

/// The real Vision requests (macOS 26 Swift API). Not covered by `make test`: a first call compiles a model for
/// minutes (plan 18 §3.2), so these run in `make ocr-check` only (D-M6-13).
public struct VisionFrameworkOCR: VisionOCR {
    public init() {}

    public func documentText(_ image: CGImage, options: OCROptions) async throws -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = options.languages.map(\.localeLanguage)
        request.textRecognitionOptions.automaticallyDetectLanguage = options.automaticallyDetectLanguage
        request.textRecognitionOptions.useLanguageCorrection = options.useLanguageCorrection
        let observations = try await request.perform(on: image)
        return observations.map { Self.text(of: $0.document) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public func accurateText(_ image: CGImage, options: OCROptions) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = options.languages.map(\.localeLanguage)
        request.automaticallyDetectsLanguage = options.automaticallyDetectLanguage
        request.usesLanguageCorrection = options.useLanguageCorrection
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Paragraphs joined by line breaks, then each table as rows of tab-separated cells.
    static func text(of document: DocumentObservation.Container) -> String {
        let paragraphs = document.paragraphs.map(\.transcript)
        let tables = document.tables.map { table in
            table.rows.map { row in row.map { $0.content.text.transcript }.joined(separator: "\t") }
                .joined(separator: "\n")
        }
        return (paragraphs + tables).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

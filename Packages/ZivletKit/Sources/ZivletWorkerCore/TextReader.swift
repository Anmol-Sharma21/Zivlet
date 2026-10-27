import EngineVision
import Foundation
import ZivletIPC

/// Copy Text in the worker (P2-103, P2-104): each input is read as a PDF (`PDFTextSource`) or an image
/// (`ImageTextSource`), the pages are combined by `TextAssembly`, and progress is the share of inputs done (a PDF's
/// pages split its share). Cancellation is checked between files and inside each source.
public struct TextReader: Sendable {
    let recognizer: any TextRecognizing
    let capabilities: @Sendable () -> VisionCapabilities
    let maximumPixels: Int

    public init(
        recognizer: any TextRecognizing = VisionTextRecognizer(),
        capabilities: @escaping @Sendable () -> VisionCapabilities = { VisionCapabilities.current },
        maximumPixels: Int = ImageTextSource.maximumHeaderPixels
    ) {
        self.recognizer = recognizer
        self.capabilities = capabilities
        self.maximumPixels = maximumPixels
    }

    public func read(_ job: TextJob, progress: @escaping @Sendable (Double) -> Void) async throws(TextError)
        -> RecognizedText
    {
        var files: [FileText] = []
        let count = Double(job.inputs.count)
        for (index, url) in job.inputs.enumerated() {
            if Task.isCancelled { throw .cancelled }
            let share: @Sendable (Double) -> Void = { part in progress((Double(index) + part) / count) }
            files.append(FileText(name: url.lastPathComponent, pages: try await pages(of: url, job: job, share: share)))
            if !ImageTextSource.isPDF(url) { share(1) }
        }
        return TextAssembly.combine(files)
    }

    private func pages(of url: URL, job: TextJob, share: @escaping @Sendable (Double) -> Void) async throws(TextError)
        -> [RecognizedPage]
    {
        if ImageTextSource.isPDF(url) {
            return try await PDFTextSource.read(url, recognizer: recognizer, languages: job.languages, progress: share)
        }
        return [
            try await ImageTextSource.read(
                url, recognizer: recognizer, languages: job.languages, maximumPixels: maximumPixels)
        ]
    }

    /// The one-time warm-up (D-M6-16).
    public func warmUp(_ languages: [LanguageTag]) async throws(TextError) {
        try await VisionWarmup.run(recognizer: recognizer, languages: languages)
    }

    public var currentCapabilities: VisionCapabilities { capabilities() }
}

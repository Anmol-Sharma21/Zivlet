import EngineVision
import Foundation
import ZivletCore
import ZivletIPC
import os

/// Copy Text in the app (P2-104, plan 18d D8): checks the dropped files, then runs one job at a time (its own
/// `vision` lane of width 1) in the worker. Vision never runs in the app: with no worker, text recognition is
/// unavailable (D-M6-8). A worker crash during a job is retried once; a second one names the file (P2-01's rule).
/// Cancelling the calling task cancels the worker's job.
public actor TextService {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    static let attempts = 2

    private let selection: WorkerSelection
    private let lane = AsyncSemaphore(width: 1)

    public init(selection: WorkerSelection) {
        self.selection = selection
    }

    public func copyText(
        _ urls: [URL], languages: [LanguageTag], progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws(TextError) -> RecognizedText {
        try Self.validate(urls)
        let connection = try await worker()
        do {
            try await lane.acquire()
        } catch {
            throw .cancelled
        }
        let result = await Self.run(connection, urls: urls, languages: languages, progress: progress)
        await lane.release()
        return try result.get()
    }

    public func capabilities() async throws(TextError) -> VisionCapabilities {
        let connection = try await worker()
        let result: Result<VisionCapabilities, TextError>
        do {
            result = try await connection.textCapabilities()
        } catch {
            throw Self.textError(error)
        }
        return try result.get()
    }

    public func warmUp(_ languages: [LanguageTag]) async throws(TextError) {
        let connection = try await worker()
        let result: Result<Void, TextError>
        do {
            result = try await connection.warmUpText(languages)
        } catch {
            throw Self.textError(error)
        }
        try result.get()
    }

    /// Local regular files only, at most `TextJob.maximumInputs` of them; the worker checks again (C2).
    static func validate(_ urls: [URL]) throws(TextError) {
        guard (1...TextJob.maximumInputs).contains(urls.count) else { throw .unreadable }
        for url in urls {
            let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard url.isFileURL, regular else { throw .unreadable }
        }
    }

    private func worker() async throws(TextError) -> WorkerConnection {
        guard case .worker(let connection, _) = await selection.choice() else { throw .unavailable }
        return connection
    }

    /// Up to two attempts, each with a fresh job id: a worker crash on the first is retried, on the second the drop
    /// is named as the cause.
    private static func run(
        _ connection: WorkerConnection, urls: [URL], languages: [LanguageTag],
        progress: @escaping @Sendable (Double) -> Void
    ) async -> Result<RecognizedText, TextError> {
        for attempt in 1...attempts {
            let job = TextJob(inputs: urls, languages: languages)
            do {
                return try await connection.recognizeText(job, progress: progress)
            } catch {
                guard error == .workerCrashed else { return .failure(textError(error)) }
                guard attempt < attempts else { break }
                logger.error("Worker crashed during a text job; retrying once")
            }
        }
        return .failure(.engineCrashedOnInput)
    }

    /// Transport and worker errors as text errors.
    static func textError(_ error: JobError) -> TextError {
        switch error {
        case .cancelled: .cancelled
        case .engineCrashedOnInput, .workerCrashed: .engineCrashedOnInput
        case .engineMissing, .engineDamaged: .unavailable
        case .unsupportedInput: .unreadable
        default: .recognitionFailed(error.logDescription)
        }
    }
}

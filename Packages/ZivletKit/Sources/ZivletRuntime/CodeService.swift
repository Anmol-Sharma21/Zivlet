import EngineVision
import Foundation
import ZivletCore
import ZivletIPC
import os

/// Read QR in the app (P2-51, plan 20b A8): checks the dropped files, then runs one job at a time in the worker, as
/// `TextService` does for Copy Text. Barcode detection never runs in the app: with no worker, codes cannot be read
/// (D-M6-8). A worker crash during a job is retried once; a second one names the drop (P2-01's rule). Cancelling the
/// calling task cancels the worker's job.
public actor CodeService {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")
    static let attempts = 2

    private let selection: WorkerSelection
    private let lane = AsyncSemaphore(width: 1)

    public init(selection: WorkerSelection) {
        self.selection = selection
    }

    public func readCodes(_ urls: [URL], progress: @escaping @Sendable (Double) -> Void = { _ in })
        async throws(CodeError) -> [FileCodes]
    {
        try Self.validate(urls)
        guard case .worker(let connection, _) = await selection.choice() else { throw .unavailable }
        do {
            try await lane.acquire()
        } catch {
            throw .cancelled
        }
        let result = await Self.run(connection, urls: urls, progress: progress)
        await lane.release()
        return try result.get()
    }

    /// Local regular files only, at least one and at most `CodeJob.maximumInputs`; the worker checks again.
    static func validate(_ urls: [URL]) throws(CodeError) {
        guard urls.count <= CodeJob.maximumInputs else { throw .tooManyFiles(limit: CodeJob.maximumInputs) }
        guard !urls.isEmpty else { throw .unreadable }
        for url in urls {
            let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard url.isFileURL, regular else { throw .unreadable }
        }
    }

    /// Up to two attempts, each with a fresh job id.
    private static func run(
        _ connection: WorkerConnection, urls: [URL], progress: @escaping @Sendable (Double) -> Void
    ) async -> Result<[FileCodes], CodeError> {
        for attempt in 1...attempts {
            do {
                return try await connection.readCodes(CodeJob(inputs: urls), progress: progress)
            } catch {
                guard error == .workerCrashed else { return .failure(codeError(error)) }
                guard attempt < attempts else { break }
                logger.error("Worker crashed during a code job; retrying once")
            }
        }
        return .failure(.engineCrashedOnInput)
    }

    /// Transport and worker errors as code errors.
    static func codeError(_ error: JobError) -> CodeError {
        switch error {
        case .cancelled: .cancelled
        case .engineCrashedOnInput, .workerCrashed: .engineCrashedOnInput
        case .engineMissing, .engineDamaged: .unavailable
        case .unsupportedInput: .unreadable
        default: .detectionFailed
        }
    }
}

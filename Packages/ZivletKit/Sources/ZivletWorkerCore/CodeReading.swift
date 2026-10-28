import EngineVision
import Foundation
import ZivletIPC

/// Read QR in the worker (P2-51, plan 20b A8): each input is read by `CodeReader`; a file that cannot be read comes
/// back with its error and the others are still read; a cancel, or an error that is not about one file, stops the
/// job. Progress is the share of files done. Cancellation is checked between files and inside the reader.
public struct CodeReading: Sendable {
    let reader: CodeReader

    public init(reader: CodeReader = CodeReader()) {
        self.reader = reader
    }

    public func read(_ job: CodeJob, progress: @escaping @Sendable (Double) -> Void) async throws(CodeError)
        -> [FileCodes]
    {
        var files: [FileCodes] = []
        for (index, url) in job.inputs.enumerated() {
            if Task.isCancelled { throw .cancelled }
            do {
                files.append(
                    FileCodes(name: url.lastPathComponent, codes: try await reader.read(url, pageLimit: job.pageLimit)))
            } catch {
                guard error.isPerFile else { throw error }
                files.append(FileCodes(name: url.lastPathComponent, error: error))
            }
            progress(Double(index + 1) / Double(job.inputs.count))
        }
        return files
    }
}

import Foundation
import ZivletCore
import ZivletEngineKit

/// The worker's answer to a PDF inspection (plan 20f E9): pre-flight with no password, under the watchdog and the
/// size and parser limits. A locked file is an answer ("shut", D-M7-36), not an error; a file qpdf cannot read is
/// refused alone with the copy a job would get.
public struct PDFPreflightReader: PDFInspecting {
    private let engine: PDFEngine

    public init(limits: QPDFLimits = .standard, watchdog: PDFWatchdog = .off) {
        engine = PDFEngine(limits: limits, watchdog: watchdog)
    }

    public func preflight(_ file: URL) async -> Result<PDFPreflight, JobError> {
        let engine = self.engine
        do {
            return .success(
                try await BlockingWork.run { _ throws(JobError) in
                    try PDFLimits.check(fileAt: file)
                    return try engine.inspect(file, password: nil)
                })
        } catch {
            return .failure(error)
        }
    }
}

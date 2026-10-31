import Darwin
import Foundation
import ZivletEngineKit

/// The qpdf-first rule (D-PDF-3, plan 20e D4): PDFKit and Quartz leave files that need repair, so every PDF they wrote
/// goes through qpdf before anyone sees it. A later PDFKit writer (Organize, Compress, Merge) calls this too, and
/// `Scripts/check-pdf-writes.sh` fails the build on one that is not named there.
public enum PDFRewrite {
    /// The page limit is for files people drop; a long TIFF makes a long PDF of Zivlet's own.
    static let limits = QPDFLimits(maxPages: 0)

    /// Rewrites `staged` where it lies (keeping its encryption and object streams, not linearized), checks the
    /// rewrite and moves it over the original. Returns the new size. On any failure the original is as it was and
    /// nothing is left beside it.
    @discardableResult
    public static func normalise(staged: URL) throws(PDFEngineError) -> Int64 {
        let rewrite = rewritePath(of: staged)
        unlink(rewrite.path)  // What a crash left here on a job's first attempt.
        do {
            try QPDFWriterBridge.write(staged, password: nil, limits: limits, mode: .preserve, to: rewrite)
            try QPDFDocumentReader.check(rewrite, password: nil, limits: limits)
        } catch {
            unlink(rewrite.path)
            throw error
        }
        guard rename(rewrite.path, staged.path) == 0 else {
            unlink(rewrite.path)
            throw .io
        }
        return PDFEngine.size(of: staged)
    }

    /// Beside the staged file, so the move is atomic; the staging folder is removed with its job.
    static func rewritePath(of staged: URL) -> URL { staged.appendingPathExtension("rewrite") }
}

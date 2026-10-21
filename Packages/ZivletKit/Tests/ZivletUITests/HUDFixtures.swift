import Foundation
import ZivletCore
import ZivletRuntime

/// Batch snapshots for HUD and card tests, without files or engines.
enum HUDFx {
    static func request(_ name: String, bytes: Int64 = 1_000, format: FormatID = .heic, to target: FormatID = .png)
        throws -> JobRequest
    {
        let input = try InputItem(url: URL(filePath: "/tmp/\(name)"), format: format, byteCount: bytes)
        return try JobRequest(input: input, operation: .convert(target), destination: URL(filePath: "/tmp"))
    }

    /// `submitted` queued items, nothing run yet.
    static func snapshot(submitted: Int, target: FormatID = .png) throws -> BatchSnapshot {
        let requests = try (0..<submitted).map { try request("file\($0).heic", to: target) }
        return BatchSnapshot(batch: BatchID(), target: target, plan: RequestPlan(requests: requests, rejections: []))
    }

    /// One item running at `progress`.
    static func running(_ progress: JobProgress, name: String = "clip.mov") throws -> BatchSnapshot {
        let request = try request(name, format: .mov, to: .mp4)
        let batch = BatchID()
        return BatchSnapshot(batch: batch, target: .mp4, plan: RequestPlan(requests: [request], rejections: []))
            .applying(.changed(batch, request.id, .running(progress)))
    }
}

extension HUDFx {
    /// A finished batch whose items all succeeded: (output name, source bytes, output bytes).
    static func finished(outputs: [(String, before: Int64, after: Int64)], target: FormatID = .png) throws
        -> BatchSnapshot
    {
        let requests = try outputs.map { try request($0.0, bytes: $0.before, to: target) }
        let batch = BatchID()
        var snapshot = BatchSnapshot(
            batch: batch, target: target, plan: RequestPlan(requests: requests, rejections: []))
        for (request, output) in zip(requests, outputs) {
            let published = PublishedOutput(
                url: URL(filePath: "/tmp/\(output.0)"), format: target, byteCount: output.after, fileID: 1,
                modified: .distantPast)
            snapshot = snapshot.applying(.changed(batch, request.id, .succeeded(published)))
        }
        return snapshot.applying(.finished(batch))
    }

    /// A finished one-item batch that failed with `error`.
    static func failed(error: JobError) throws -> BatchSnapshot {
        let request = try request("clip.mov", format: .mov, to: .mp4)
        let batch = BatchID()
        return BatchSnapshot(batch: batch, target: .mp4, plan: RequestPlan(requests: [request], rejections: []))
            .applying(.changed(batch, request.id, .failed(error))).applying(.finished(batch))
    }
}

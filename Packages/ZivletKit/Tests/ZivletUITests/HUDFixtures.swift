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

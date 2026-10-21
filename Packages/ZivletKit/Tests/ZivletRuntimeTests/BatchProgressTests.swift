import Foundation
import Testing
import ZivletCore

@testable import ZivletRuntime

@Suite("Batch progress: weighted by size, carries the current item's details (D7)")
struct BatchProgressTests {
    static func request(_ name: String, bytes: Int64, format: FormatID, to target: FormatID) throws -> JobRequest {
        let input = try InputItem(url: URL(filePath: "/tmp/\(name)"), format: format, byteCount: bytes)
        return try JobRequest(input: input, operation: .convert(target), destination: URL(filePath: "/tmp"))
    }

    @Test func aLargeVideoDominatesTheBatchFraction() throws {
        let video = try Self.request("film.mov", bytes: 1_000_000_000, format: .mov, to: .mp4)
        let audio = try Self.request("blip.wav", bytes: 1_000, format: .wav, to: .mp3)
        let batch = BatchID()
        let start = BatchSnapshot(
            batch: batch, target: .mp4, plan: RequestPlan(requests: [video, audio], rejections: []))
        let running = start.applying(.changed(batch, video.id, .running(JobProgress(fraction: 0.5))))
            .applying(.changed(batch, audio.id, .cancelled))
        #expect(abs(running.fraction - 0.5) < 0.001)
    }

    @Test func theCurrentItemsProgressDetailsAreExposed() throws {
        let video = try Self.request("film.mov", bytes: 10, format: .mov, to: .mp4)
        let batch = BatchID()
        let progress = JobProgress(fraction: nil, stage: 0, stageCount: 1, bytesWritten: 12_400_000, eta: nil)
        let snapshot = BatchSnapshot(batch: batch, target: .mp4, plan: RequestPlan(requests: [video], rejections: []))
            .applying(.changed(batch, video.id, .running(progress)))
        #expect(snapshot.currentProgress == progress)
        #expect(snapshot.isIndeterminate)
    }

    @Test func refusedItemsWeighAsMuchAsTheSmallestFile() throws {
        let image = try Self.request("a.heic", bytes: 4, format: .heic, to: .jpg)
        let batch = BatchID()
        let rejection = RequestRejection(url: URL(filePath: "/tmp/x.xyz"), error: .unsupportedInput(.unknownFormat))
        let snapshot = BatchSnapshot(
            batch: batch, target: .jpg, plan: RequestPlan(requests: [image], rejections: [rejection]))
        #expect(abs(snapshot.fraction - 0.5) < 0.001)
    }
}

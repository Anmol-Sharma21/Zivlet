import EngineVision
import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletIPC

/// One value of every request, reply and event case, built from fixed paths (nothing is read or written).
enum IPCFixtures {
    static let job = JobID(UUID(uuidString: "6F1E2D3C-4B5A-4978-8867-564534231201") ?? UUID())
    static let staged = URL(fileURLWithPath: "/private/tmp/out/.zivlet-\(job)/staged.jpg")

    static func request() -> JobRequest {
        do {
            let input = try InputItem(
                url: URL(fileURLWithPath: "/private/tmp/in/photo.png"), format: .png, byteCount: 42)
            return try JobRequest(
                id: job, input: input, operation: .convert(.jpg), destination: URL(fileURLWithPath: "/private/tmp/out"))
        } catch {
            preconditionFailure("fixture request: \(error)")
        }
    }

    static func plan() -> ExecutionPlan {
        do {
            return try ExecutionPlan(
                engine: .image, stages: [.ffmpeg(FFmpegStage(argv: ["fake"], expectedDurationMicros: 1_000))],
                stageWeights: [1], lanes: [.cpu], outputFormat: .jpg, stagedFile: staged, notes: [.alphaFlattened])
        } catch {
            preconditionFailure("fixture plan: \(error)")
        }
    }

    static let output = StagedOutput(format: .jpg, url: staged, byteCount: 1_234, withdrawnNotes: [.alphaFlattened])

    static let capabilities = WorkerCapabilities(engines: [
        EngineCapability(
            id: .image,
            routes: [
                RouteCapability(pair: ConversionPair(source: .png, target: .jpg), availability: .available),
                RouteCapability(
                    pair: ConversionPair(source: .png, target: .webp), availability: .unavailable(["libwebp"])),
            ])
    ])

    static var requests: [WorkerRequest] {
        var all: [WorkerRequest] = [
            .ping, .capabilities, .prepare(request(), JobWorkspace(job: job, stagedFile: staged)),
            .execute(job, plan(), outputByteLimit: 9_000), .execute(job, plan(), outputByteLimit: nil),
            .verify(output, plan()), .cancel(job), .recognizeText(textJob), .textCapabilities,
            .warmUpText(job, [.hindi, .english]),
        ]
        #if DEBUG
            all += [.selfKillForTesting(afterMilliseconds: 25), .setIdleForTesting(seconds: 5)]
        #endif
        return all
    }

    static let replies: [WorkerReply] = [
        .pong(pid: 321, osBuild: "26A428"), .capabilities(capabilities), .planned(plan()), .staged(output), .verified,
        .failed(.unsupportedInput(.notAFile)), .failed(.cancelled), .accepted, .text(recognized),
        .textFailed(.copyingNotAllowed), .textCapabilities(VisionCapabilities(languages: [.hindi], osBuild: "26A1")),
    ]

    static let textJob = TextJob(
        id: job, inputs: [URL(fileURLWithPath: "/private/tmp/in/photo.png")], languages: [.hindi, .english])

    static let recognized = TextAssembly.combine([
        FileText(name: "photo.png", pages: [RecognizedPage(text: "आज मौसम अच्छा है")])
    ])

    static let events: [WorkerEvent] = [
        .progress(job, JobProgress(fraction: 0.5, stage: 0, stageCount: 1)), .progress(job, JobProgress(fraction: nil)),
        .spawned(job, 4242),
    ]
}

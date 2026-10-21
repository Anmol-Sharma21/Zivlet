import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// Output checks after a run (03b §5.9): the container the target promises, the expected stream kind, WebM codecs,
/// and the duration within max(0.25 s, 1 %) of the plan.
enum MediaVerifier {
    static let minimumToleranceMicros: Int64 = 250_000
    static let webmVideo: Set<String> = ["vp8", "vp9", "av1"]
    static let webmAudio: Set<String> = ["opus", "vorbis"]

    static func check(_ info: MediaInfo, target: FormatID, expectedMicros: Int64?, registry: FormatRegistry)
        throws(JobError)
    {
        guard MediaProbe.confirms(info, source: target) else {
            throw .verificationFailed("The output is not a \(target.rawValue.uppercased()) file.")
        }
        let isAudio = registry.format(target).category == .audio
        guard isAudio ? info.primaryAudio != nil : info.primaryVideo != nil else {
            throw .verificationFailed(isAudio ? "The output has no audio." : "The output has no video.")
        }
        if target == .webm { try checkWebM(info) }
        if let expectedMicros, let actual = info.durationMicros {
            let tolerance = max(minimumToleranceMicros, expectedMicros / 100)
            guard abs(actual - expectedMicros) <= tolerance else {
                throw .verificationFailed(
                    "The output is \(actual / 1_000) ms long, expected \(expectedMicros / 1_000) ms.")
            }
        }
    }

    private static func checkWebM(_ info: MediaInfo) throws(JobError) {
        let videoOK = info.primaryVideo.map { webmVideo.contains($0.codec) } ?? false
        let audioOK = info.audioStreams.allSatisfy { webmAudio.contains($0.codec) }
        guard videoOK, audioOK else { throw .verificationFailed("The WebM output uses codecs browsers can't play.") }
    }
}

/// Runner results and errors → `JobError` (03b §5.9 error row).
enum MediaFailure {
    static func launch(
        _ runner: any ProcessRunning, _ request: SubprocessRequest,
        spawned: @escaping @Sendable (Int32) -> Void = { _ in },
        onLine: @escaping @Sendable (String) -> Void
    ) async throws(JobError) -> SubprocessResult {
        do {
            return try await runner.run(request, onSpawn: spawned, onLine: onLine)
        } catch {
            throw error.jobError(engine: .media)
        }
    }

    static func check(_ result: SubprocessResult) throws(JobError) {
        switch result.termination {
        case .exited(0): return
        case .exited(let status):
            if result.stderrTail.contains("No space left on device") { throw .diskFull }
            throw .processFailed(status: status, stderrTail: result.stderrTail)
        case .signaled(let signal): throw .crashed(signal: signal)
        }
    }

    static func map(_ error: MediaPlanError) -> JobError {
        switch error {
        case .pairNotSupported(let source, let target): .pairNotSupported(source, target)
        case .noAudioTrack: .unsupportedInput(.noAudioTrack)
        case .noVideoTrack: .unsupportedInput(.noVideoTrack)
        case .invalidPath: .unsupportedInput(.notAFile)
        case .invalidOption, .invalidPass: .internalInvariant("media planner refused its defaults: \(error)")
        }
    }
}

enum MediaFiles {
    /// Size of a file, 0 when it is missing (verification then fails with "empty").
    static func size(of url: URL) -> Int64 {
        var info = stat()
        return stat(url.path, &info) == 0 ? Int64(info.st_size) : 0
    }
}

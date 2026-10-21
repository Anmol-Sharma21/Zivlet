import EngineTestSupport
import Foundation
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

/// Answers playability from a fixed value and counts the questions.
final class FakePlayability: PlayabilityChecking {
    let answer: Bool
    private let asked = Mutex<[URL]>([])

    init(_ answer: Bool) { self.answer = answer }

    var questions: [URL] { asked.withLock { $0 } }

    func isPlayable(_ url: URL, as format: FormatID) async -> Bool {
        asked.withLock { $0.append(url) }
        return answer
    }
}

@Suite("Media verification: stream count and AVFoundation playability (G-4, 03b §5.9)")
struct MediaVerifierTests {
    static let movie = ProbeJSON.file(
        "mov,mp4,m4a,3gp,3g2,mj2", duration: "\"1.0\"",
        ProbeJSON.stream(0, "video", "h264", #","width":64,"height":48,"pix_fmt":"yuv420p""#),
        ProbeJSON.stream(1, "audio", "aac", #","sample_rate":"48000","channels":2"#))
    static let silentMovie = ProbeJSON.file(
        "mov,mp4,m4a,3gp,3g2,mj2", duration: "\"1.0\"",
        ProbeJSON.stream(0, "video", "h264", #","width":64,"height":48,"pix_fmt":"yuv420p""#))
    static let movieWithTimecode = ProbeJSON.file(
        "mov,mp4,m4a,3gp,3g2,mj2", duration: "\"1.0\"",
        ProbeJSON.stream(0, "video", "h264", #","width":64,"height":48,"pix_fmt":"yuv420p""#),
        ProbeJSON.stream(1, "audio", "aac", #","sample_rate":"48000","channels":2"#),
        ProbeJSON.stream(2, "data", "tmcd"))

    func verify(staged: String, to target: FormatID = .mov, playable: Bool = true) async throws -> FakePlayability {
        let playability = FakePlayability(playable)
        let source: FormatID = target == .mp4 ? .mov : .mp4
        let name = "in.\(source.rawValue)"
        let rig = try MediaRig(probes: [name: Self.movie, "staged": staged], playability: playability)
        let request = try rig.request(name, source, to: target)
        let plan = try await rig.engine.prepare(request, workspace: rig.workspace(request))
        try await rig.engine.verify(try rig.staged(request), plan: plan)
        return playability
    }

    @Test func aMatchingMovieIsCheckedForPlayability() async throws {
        let playability = try await verify(staged: Self.movie)
        #expect(playability.questions.count == 1)
    }

    @Test func dataStreamsTheMuxerAddsDoNotCount() async throws {
        _ = try await verify(staged: Self.movieWithTimecode)
    }

    @Test func aMissingStreamIsRefused() async throws {
        await #expect(throws: JobError.verificationFailed("The output has 1 stream, expected 2.")) {
            _ = try await verify(staged: Self.silentMovie)
        }
    }

    @Test(arguments: [FormatID.mov, .mp4])
    func anUnplayableMovieIsRefused(target: FormatID) async throws {
        let message = "The \(target.rawValue.uppercased()) output can't be played by macOS."
        await #expect(throws: JobError.verificationFailed(message)) {
            _ = try await verify(staged: Self.movie, to: target, playable: false)
        }
    }

    @Test func otherContainersAreNotAskedAboutPlayability() async throws {
        let mkv = ProbeJSON.file(
            "matroska,webm", duration: "\"1.0\"",
            ProbeJSON.stream(0, "video", "h264", #","width":64,"height":48,"pix_fmt":"yuv420p""#),
            ProbeJSON.stream(1, "audio", "aac", #","sample_rate":"48000","channels":2"#))
        let playability = try await verify(staged: mkv, to: .mkv, playable: false)
        #expect(playability.questions.isEmpty)
    }

    @Test(arguments: [
        (["-map", "0:0", "-map", "0:1", "-c", "copy"], 2), (["-filter_complex", "[0:0]fps=10[v]", "-an"], 1),
        (["-filter_complex", "x[v]", "-map", "[v]", "-map", "0:1"], 2),
    ])
    func theExpectedStreamsAreTheMappedOnes(argv: [String], count: Int) {
        #expect(MediaVerifier.expectedStreams(argv) == count)
    }
}

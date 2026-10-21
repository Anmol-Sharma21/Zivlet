import Foundation
import Testing
import ZivletCore

/// One file of the hostile corpus (P1-62): what it is dropped onto and how it must end.
struct HostileCase: Sendable, CustomTestStringConvertible {
    enum Outcome: Sendable, Equatable {
        /// Refused with exactly this error, before or during the job.
        case refused(JobError)
        /// Converted; the output must not contain the canary.
        case converted
    }

    let file: String
    let target: FormatID
    let outcome: Outcome
    /// Symlinks and FIFOs are dropped where they are; everything else from a copy.
    var isSpecial = false

    var testDescription: String { "\(file) → \(target.rawValue)" }
}

/// Where `Fixtures/hostile/generate.sh` wrote the corpus, and the canary's secret.
enum HostileCorpus {
    static var directory: URL {
        ProcessInfo.processInfo.environment["ZIVLET_HOSTILE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? MatrixRig.repository.appending(path: "build/fixtures/hostile", directoryHint: .isDirectory)
    }

    static func token() throws -> Data {
        let url = directory.appending(path: "canary.txt")
        guard let token = try? Data(contentsOf: url), token.count >= 32 else {
            throw MatrixFailure("no hostile corpus in \(directory.path): run Fixtures/hostile/generate.sh first")
        }
        return token
    }

    static let mismatch = JobError.unsupportedInput(.contentMismatch)
    static let cases: [HostileCase] = [
        HostileCase(file: "playlist.mp4", target: .mov, outcome: .refused(mismatch)),
        HostileCase(file: "concat.mkv", target: .mp4, outcome: .refused(mismatch)),
        HostileCase(file: "lavfi-graph.mp4", target: .mov, outcome: .refused(mismatch)),
        HostileCase(file: "truncated.mp4", target: .mov, outcome: .refused(.unsupportedInput(.unreadable))),
        // ImageIO reports no properties for a huge header without pixel data, so both are refused before decoding.
        HostileCase(file: "huge-ihdr.png", target: .jpg, outcome: .refused(.unsupportedInput(.unreadable))),
        HostileCase(file: "archive.tiff", target: .jpg, outcome: .refused(mismatch)),
        HostileCase(file: "pages-5000.tiff", target: .pdf, outcome: .converted),
        HostileCase(file: "entities.svg", target: .png, outcome: .refused(.unsupportedInput(.unreadable))),
        HostileCase(file: "external-href.svg", target: .png, outcome: .converted),
        HostileCase(file: "bomb.svgz", target: .png, outcome: .refused(.unsupportedInput(.tooLarge))),
        HostileCase(file: "huge-canvas.webp", target: .jpg, outcome: .refused(.unsupportedInput(.unreadable))),
        HostileCase(file: "link.png", target: .jpg, outcome: .refused(.unsupportedInput(.notAFile)), isSpecial: true),
        HostileCase(file: "stream.wav", target: .mp3, outcome: .refused(.unsupportedInput(.notAFile)), isSpecial: true),
    ]
}

/// Every corpus file is refused with its error or converted without leaking the canary, and nothing crashes: a
/// helper killed by a signal would surface as `.crashed`, which no case expects (opt-in with the matrix).
@Suite("Hostile corpus (opt-in: ZIVLET_MATRIX)", .enabled(if: MatrixEnvironment.isEnabled), .timeLimit(.minutes(5)))
struct HostileCorpusTests {
    @Test(arguments: HostileCorpus.cases)
    func isRefusedOrConvertedSafely(hostile: HostileCase) async throws {
        let token = try HostileCorpus.token()
        let rig = try await MatrixRig.shared()
        let input = HostileCorpus.directory.appending(path: hostile.file)
        let run = try await rig.run(input, to: hostile.target, copying: !hostile.isSpecial)
        switch (run, hostile.outcome) {
        case (.refused(let error), .refused(let expected)):
            #expect(error == expected)
        case (.converted(let output), .converted):
            defer { output.discard() }
            let bytes = try Data(contentsOf: output.url)
            #expect(bytes.range(of: token) == nil, "the canary leaked into the output")
        case (.converted(let output), .refused(let expected)):
            output.discard()
            Issue.record("converted, expected \(expected)")
        case (.refused(let error), .converted):
            Issue.record("refused with \(error), expected a conversion")
        }
    }

    @Test func everyCorpusFileHasACase() throws {
        _ = try HostileCorpus.token()
        let names = try FileManager.default.contentsOfDirectory(atPath: HostileCorpus.directory.path)
            .filter { !$0.hasPrefix(".") && $0 != "canary.txt" }
        #expect(Set(names) == Set(HostileCorpus.cases.map(\.file)))
    }
}

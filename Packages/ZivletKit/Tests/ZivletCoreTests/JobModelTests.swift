import Foundation
import Testing

@testable import ZivletCore

@Suite("Job values: request, input, error, state (02 §7.2, §9)")
struct JobModelTests {
    static let photo = URL(fileURLWithPath: "/Users/me/Pictures/photo.HEIC")

    static func input(_ url: URL = photo, _ format: FormatID = .heic, bytes: Int64 = 1_000) throws -> InputItem {
        try InputItem(url: url, format: format, byteCount: bytes)
    }

    @Test func aRequestKeepsItsValuesAndNamesItsTarget() throws {
        let request = try JobRequest(
            input: Self.input(), operation: .convert(.jpg), destination: Self.photo.deletingLastPathComponent())
        #expect(request.target == .jpg)
        #expect(request.pair == ConversionPair(source: .heic, target: .jpg))
        #expect(request.destination.path == "/Users/me/Pictures")
        #expect(request.input.fileName == "photo.HEIC")
    }

    @Test func aPairOutsideTheCatalogIsRefused() throws {
        #expect(throws: JobError.pairNotSupported(.heic, .mp3)) {
            try JobRequest(input: Self.input(), operation: .convert(.mp3), destination: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test(arguments: ["/a/../photo.heic", "/a/pho\u{7F}to.heic", "/a/photo\n.heic", "/"])
    func inputsNeedASafeAbsoluteFilePath(path: String) {
        #expect(throws: JobError.unsupportedInput(.notAFile)) { try Self.input(URL(fileURLWithPath: path)) }
    }

    @Test func inputsRefuseNegativeSizesAndRemoteURLs() throws {
        #expect(throws: JobError.unsupportedInput(.notAFile)) { try Self.input(bytes: -1) }
        let remote = try #require(URL(string: "https://example.com/a.heic"))
        #expect(throws: JobError.unsupportedInput(.notAFile)) { try Self.input(remote) }
    }

    @Test func destinationsMustBeAbsoluteFolders() throws {
        #expect(throws: JobError.invalidDestination) {
            try JobRequest(input: Self.input(), operation: .convert(.png), destination: try #require(URL(string: "x")))
        }
    }

    @Test func requestsRoundTripAndDecodingRevalidates() throws {
        let request = try JobRequest(
            input: Self.input(), operation: .convert(.png), destination: URL(fileURLWithPath: "/tmp"))
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(JobRequest.self, from: data) == request)
        let tampered = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"png\"", with: "\"mp3\"")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(JobRequest.self, from: Data(tampered.utf8)) }
    }

    /// NFR-6: the public log line names the case and its numbers, never a path or the helper's stderr.
    @Test(arguments: [
        (
            JobError.processFailed(status: 1, stderrTail: "file:/Users/me/a.mp4: Permission denied"),
            "processFailed(status: 1)"
        ),
        (.permissionDenied(folder: "/Users/me/Secret"), "permissionDenied"),
        (.verificationFailed("/Users/me/x"), "verificationFailed"),
        (.internalInvariant("/Users/me/x"), "internalInvariant"),
        (.unsupportedInput(.tooLarge), "unsupportedInput(tooLarge)"),
        (.routeUnavailable(.mp3, .ogg, ["libvorbis"]), "routeUnavailable(mp3 → ogg, missing: libvorbis)"),
        (.pairNotSupported(.mp3, .png), "pairNotSupported(mp3 → png)"),
        (.engineMissing(.media), "engineMissing(media)"),
        (.engineDamaged(.media), "engineDamaged(media)"),
        (.crashed(signal: 9), "crashed(signal: 9)"),
        (.helperFailed(errno: 24), "helperFailed(errno: 24)"),
        (.publishFailed(errno: 17), "publishFailed(errno: 17)"),
        (.diskFull, "diskFull"), (.stalled, "stalled"), (.cancelled, "cancelled"),
        (.invalidDestination, "invalidDestination"), (.writeFailed("/Users/me/x"), "writeFailed"),
    ])
    func theLogDescriptionHoldsNoPathsOrStderr(error: JobError, expected: String) {
        #expect(error.logDescription == expected)
        #expect(!error.logDescription.contains("/Users"))
    }

    @Test func errorsRoundTripThroughJSON() throws {
        let errors: [JobError] = [
            .pairNotSupported(.png, .mp3), .unsupportedInput(.noAudioTrack),
            .routeUnavailable(.mp3, .ogg, ["libvorbis"]),
            .engineMissing(.media), .invalidDestination, .permissionDenied(folder: "/Volumes/RO"), .diskFull,
            .processFailed(status: 1, stderrTail: "boom"), .crashed(signal: 11), .cancelled,
            .verificationFailed("no audio"), .publishFailed(errno: 17), .internalInvariant("x"),
            .helperFailed(errno: 24), .writeFailed("encoder"), .engineDamaged(.media),
        ]
        let data = try JSONEncoder().encode(errors)
        #expect(try JSONDecoder().decode([JobError].self, from: data) == errors)
    }

    @Test(arguments: [(-0.5, 0.0), (0.25, 0.25), (1.7, 1.0)])
    func progressIsClampedToTheUnitRange(raw: Double, expected: Double) {
        #expect(JobProgress(fraction: raw).fraction == expected)
    }

    @Test func nonFiniteProgressIsIndeterminate() {
        #expect(JobProgress(fraction: .nan).fraction == nil)
        #expect(JobProgress(fraction: nil).fraction == nil)
    }

    @Test func onlySucceededFailedAndCancelledAreTerminal() {
        let output = PublishedOutput(url: Self.photo, format: .jpg, byteCount: 5, fileID: 9, modified: .distantPast)
        let terminal: [JobState] = [.succeeded(output), .failed(.diskFull), .cancelled]
        let live: [JobState] = [.queued, .preparing, .running(JobProgress(fraction: 0.5)), .verifying, .publishing]
        #expect(terminal.allSatisfy { $0.isTerminal })
        #expect(terminal.map(\.published) == [output, nil, nil])
        #expect(!live.contains { $0.isTerminal })
    }

    @Test func identifiersAreUniqueAndStable() throws {
        let id = JobID()
        #expect(id != JobID())
        #expect(try JSONDecoder().decode(JobID.self, from: JSONEncoder().encode(id)) == id)
        #expect(BatchID().description.count == 36)
    }

    @Test func qualityTierRawValuesAreStable() {
        #expect(QualityTier.allCases.map(\.rawValue) == ["small", "standard", "best"])
    }
}

import Darwin
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

@Suite("Drop → requests, error copy, batch snapshots, undo (P1-33, P1-15, FR-15)")
struct RequestsAndCopyTests {
    @Test func validFilesBecomeRequestsBesideTheOriginal() throws {
        let box = try Sandbox()
        let photo = try box.file("Photo.HEIC")
        let plan = JobRequestFactory(fallbackFolder: box.dir.appending(path: "Downloads")).requests(
            for: [photo], target: .jpg)
        let request = try #require(plan.requests.first)
        #expect(plan.rejections.isEmpty)
        #expect(request.input.format == .heic && request.input.byteCount == 4 && request.target == .jpg)
        #expect(request.destination.path == box.dir.path)
    }

    @Test func refusalsAreTypedPerItem() throws {
        let box = try Sandbox()
        let folder = box.dir.appending(path: "Album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let urls = [
            try box.file("notes.xyz"), try box.file("song.mp3"), folder, box.dir.appending(path: "missing.png"),
        ]
        let plan = JobRequestFactory().requests(for: urls, target: .png)
        #expect(plan.requests.isEmpty)
        #expect(
            plan.rejections.map(\.error) == [
                .unsupportedInput(.unknownFormat), .pairNotSupported(.mp3, .png), .unsupportedInput(.notAFile),
                .unsupportedInput(.unreadable),
            ])
    }

    @Test func aReadOnlyFolderFallsBackToDownloads() throws {
        let box = try Sandbox()
        let locked = box.dir.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try Data("x".utf8).write(to: locked.appending(path: "a.png"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let downloads = box.dir.appending(path: "Downloads")
        let plan = JobRequestFactory(fallbackFolder: downloads).requests(
            for: [locked.appending(path: "a.png")], target: .jpg)
        #expect(plan.requests.first?.destination == downloads)
    }

    static let everyError: [JobError] = [
        .pairNotSupported(.mp3, .png), .unsupportedInput(.notAFile), .unsupportedInput(.unreadable),
        .unsupportedInput(.unknownFormat), .unsupportedInput(.contentMismatch), .unsupportedInput(.noAudioTrack),
        .unsupportedInput(.noVideoTrack), .unsupportedInput(.tooLarge), .routeUnavailable(.mp3, .ogg, ["libvorbis"]),
        .engineMissing(.media), .engineMissing(.image), .invalidDestination, .permissionDenied(folder: "/Volumes/Card"),
        .diskFull, .processFailed(status: 1, stderrTail: "a\nb"), .crashed(signal: 11), .stalled, .cancelled,
        .verificationFailed("short"), .publishFailed(errno: EACCES), .internalInvariant("bug"),
        .helperFailed(errno: EMFILE), .writeFailed("encoder"),
    ]

    @Test(arguments: everyError)
    func everyErrorHasOneSentenceOfCopy(error: JobError) {
        let copy = JobErrorCopy.copy(for: error)
        #expect(copy.message.hasSuffix(".") && !copy.message.contains("Tangerine"))
        #expect(copy.message.count < 80)
    }

    @Test func onlyDebugBuildsNameTheDeveloperToolFolders() {
        let detail = JobErrorCopy.copy(for: .engineMissing(.media)).detail ?? ""
        #if DEBUG
            #expect(detail.contains("ZIVLET_FFMPEG_DIR"))
        #else
            #expect(!detail.contains("/opt/homebrew") && !detail.contains("/usr/local"))
        #endif
    }

    @Test func aHelperThatCannotStartSaysWhy() {
        let crowded = JobErrorCopy.copy(for: .helperFailed(errno: EMFILE))
        #expect(crowded.message == "Zivlet couldn't start its converter.")
        #expect(crowded.detail?.contains("fewer files at once") == true)
        #expect(JobErrorCopy.copy(for: .helperFailed(errno: ECHILD)).detail == String(cString: strerror(ECHILD)) + ".")
    }

    @Test func copyNamesFormatsFoldersAndDetails() {
        #expect(
            JobErrorCopy.copy(for: .pairNotSupported(.mp3, .png)).message == "Zivlet can't convert MP3 files to PNG.")
        #expect(JobErrorCopy.copy(for: .routeUnavailable(.mp3, .ogg, ["libvorbis"])).detail == "Missing: libvorbis.")
        #expect(JobErrorCopy.copy(for: .permissionDenied(folder: "/Volumes/Card")).message.contains("“Card”"))
        let tail = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let detail = JobErrorCopy.copy(for: .processFailed(status: 1, stderrTail: tail)).detail ?? ""
        #expect(detail.hasPrefix("Exit status 1.\nline 9") && detail.hasSuffix("line 20"))
    }

    static func snapshot() throws -> (BatchSnapshot, [JobRequest]) {
        let box = try Sandbox()
        let requests = try [box.request("a.heic", .heic, to: .jpg), box.request("b.heic", .heic, to: .jpg)]
        let plan = RequestPlan(
            requests: requests, rejections: [RequestRejection(url: box.dir.appending(path: "c.txt"), error: .diskFull)])
        return (BatchSnapshot(batch: BatchID(), target: .jpg, plan: plan), requests)
    }

    @Test func snapshotsFollowEventsAndAverageProgress() throws {
        let (start, requests) = try Self.snapshot()
        let batch = start.batch
        let output = PublishedOutput(
            url: URL(fileURLWithPath: "/x/a.jpg"), format: .jpg, byteCount: 3, fileID: 1, modified: .distantPast)
        let running = start.applying(.changed(batch, requests[0].id, .running(JobProgress(fraction: 0.5))))
        #expect(abs(running.fraction - 0.5) < 1e-9)
        #expect(running.current?.item.name == "a.heic" && running.doneCount == 1)
        let done =
            running
            .applying(.changed(batch, requests[0].id, .succeeded(output)))
            .applying(.noted(batch, requests[1].id, [.alphaFlattened]))
            .applying(.changed(batch, requests[1].id, .cancelled))
            .applying(.changed(BatchID(), requests[1].id, .preparing))
            .applying(.finished(batch))
        #expect(done.isFinished && done.fraction == 1 && done.outputs == [output] && done.cancelledCount == 1)
        #expect(done.failures.map(\.name) == ["c.txt"] && done.items[1].notes == [.alphaFlattened])
        #expect(done.current == nil)
    }
}

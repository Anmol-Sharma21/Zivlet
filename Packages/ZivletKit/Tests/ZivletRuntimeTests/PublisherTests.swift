import Darwin
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// A temporary folder on the boot volume with helpers for job requests and staged files.
struct Sandbox {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-rt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ name: String, _ contents: String = "data") throws -> URL {
        let url = dir.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func request(_ name: String, _ format: FormatID, to target: FormatID, quarantine: Data? = nil) throws -> JobRequest
    {
        let input = try InputItem(url: dir.appending(path: name), format: format, byteCount: 4, quarantine: quarantine)
        return try JobRequest(input: input, operation: .convert(target), destination: dir)
    }

    /// Claims staging and writes `contents` into it, as an engine would.
    func staged(_ request: JobRequest, publisher: Publisher, contents: String = "output") throws -> StagedOutput {
        let workspace = try publisher.claimStaging(for: request)
        try Data(contents.utf8).write(to: workspace.stagedFile)
        return StagedOutput(format: request.target, url: workspace.stagedFile, byteCount: Int64(contents.utf8.count))
    }

    var listing: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    var isCaseSensitive: Bool {
        (try? dir.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames)
            == true
    }
}

@Suite("Publisher: hidden staging, exclusive rename, collisions, quarantine (P1-30, 03a §4.3)")
struct PublisherTests {
    let publisher = Publisher()

    @Test func stagingIsAHiddenFileInTheDestinationClaimedExclusively() throws {
        let box = try Sandbox()
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let workspace = try publisher.claimStaging(for: request)
        #expect(workspace.stagedFile.deletingLastPathComponent().path == box.dir.path)
        #expect(workspace.stagedFile.lastPathComponent == ".zivlet-\(request.id).jpg")
        #expect(throws: JobError.publishFailed(errno: EEXIST)) { try publisher.claimStaging(for: request) }
    }

    @Test func publishRenamesToTheConvertedName() throws {
        let box = try Sandbox()
        try box.file("photo.heic")
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let published = try publisher.publish(try box.staged(request, publisher: publisher), for: request)
        #expect(published.url.lastPathComponent == "photo.jpg")
        #expect(published.byteCount == 6 && published.fileID != 0 && published.format == .jpg)
        #expect(box.listing == ["photo.heic", "photo.jpg"])
    }

    @Test func anExistingFileIsNeverReplaced() throws {
        let box = try Sandbox()
        try box.file("song.mp3", "keep me")
        try box.file("song 2.mp3", "keep me too")
        let request = try box.request("song.wav", .wav, to: .mp3)
        let published = try publisher.publish(try box.staged(request, publisher: publisher), for: request)
        #expect(published.url.lastPathComponent == "song 3.mp3")
        #expect(try String(contentsOf: box.dir.appending(path: "song.mp3"), encoding: .utf8) == "keep me")
    }

    @Test func collisionsFollowTheVolumeCaseRule() throws {
        let box = try Sandbox()
        try box.file("Clip.MP4", "existing")
        let request = try box.request("clip.mov", .mov, to: .mp4)
        let published = try publisher.publish(try box.staged(request, publisher: publisher), for: request)
        #expect(published.url.lastPathComponent == (box.isCaseSensitive ? "clip.mp4" : "clip 2.mp4"))
    }

    @Test func fiftyConcurrentPublishesGetFiftyDistinctNames() async throws {
        let box = try Sandbox()
        let names = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<50 {
                let request = try box.request("a.jpg", .jpg, to: .png)
                let staged = try box.staged(request, publisher: publisher)
                group.addTask { try publisher.publish(staged, for: request).url.lastPathComponent }
            }
            return try await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        #expect(names.count == 50)
        #expect(names.contains("a.png") && names.contains("a 50.png"))
        #expect(!box.listing.contains { $0.hasPrefix(Publisher.stagingPrefix) })
    }

    @Test func quarantineIsCopiedFromTheInput() throws {
        let box = try Sandbox()
        let value = Data("0083;65f0a1b2;Safari;".utf8)
        let source = try box.file("download.png")
        _ = value.withUnsafeBytes { setxattr(source.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) }
        let read = try #require(Publisher.quarantine(of: source))
        let request = try box.request("download.png", .png, to: .jpg, quarantine: read)
        let published = try publisher.publish(try box.staged(request, publisher: publisher), for: request)
        #expect(Publisher.quarantine(of: published.url) == value)
        #expect(Publisher.quarantine(of: try box.file("plain.txt")) == nil)
    }

    @Test func discardRemovesStagingAndToleratesItsAbsence() throws {
        let box = try Sandbox()
        let request = try box.request("a.wav", .wav, to: .mp3)
        let workspace = try publisher.claimStaging(for: request)
        try publisher.discard(workspace)
        try publisher.discard(workspace)
        #expect(box.listing.isEmpty)
    }

    @Test func claimErrorsAreTyped() throws {
        let box = try Sandbox()
        let missing = try JobRequest(
            input: InputItem(url: box.dir.appending(path: "a.wav"), format: .wav, byteCount: 1),
            operation: .convert(.mp3), destination: box.dir.appending(path: "gone"))
        #expect(throws: JobError.invalidDestination) { try publisher.claimStaging(for: missing) }
        let locked = box.dir.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let readOnly = try JobRequest(
            input: InputItem(url: locked.appending(path: "a.wav"), format: .wav, byteCount: 1),
            operation: .convert(.mp3),
            destination: locked)
        #expect(throws: JobError.permissionDenied(folder: locked.path)) { try publisher.claimStaging(for: readOnly) }
        #expect(Publisher.claimError(ENOSPC, folder: locked) == .diskFull)
        #expect(Publisher.claimError(EIO, folder: locked) == .publishFailed(errno: EIO))
    }

    @Test func aPublishedFileThatCannotBeStampedIsRemovedAgain() throws {
        let box = try Sandbox()
        let request = try box.request("a.wav", .wav, to: .mp3)
        let blind = Publisher(namer: OutputNamer(), registry: .standard) { _ in
            errno = EIO
            return nil
        }
        #expect(throws: JobError.publishFailed(errno: EIO)) {
            try blind.publish(try box.staged(request, publisher: blind), for: request)
        }
        #expect(box.listing.isEmpty)
    }

    /// Someone else who can write in the folder swaps the staged file for a symlink or a hard link to another file:
    /// it is never published under the converted name and the other file is left alone.
    @Test(arguments: [true, false])
    func aStagedFileReplacedByALinkIsRefused(symbolic: Bool) throws {
        let box = try Sandbox()
        let victim = try box.file("victim.txt", "precious")
        let request = try box.request("a.wav", .wav, to: .mp3)
        let staged = try box.staged(request, publisher: publisher)
        if symbolic {
            try FileManager.default.removeItem(at: staged.url)
            try FileManager.default.createSymbolicLink(at: staged.url, withDestinationURL: victim)
        } else {
            try FileManager.default.removeItem(at: staged.url)
            try FileManager.default.linkItem(at: victim, to: staged.url)
        }
        #expect(throws: JobError.verificationFailed(StagedFile.replacedMessage)) {
            try publisher.publish(staged, for: request)
        }
        #expect(!box.listing.contains("a.mp3"))
        #expect(try String(contentsOf: victim, encoding: .utf8) == "precious")
    }

    @Test func publishingAMissingStagedFileFails() throws {
        let box = try Sandbox()
        let request = try box.request("a.wav", .wav, to: .mp3)
        let ghost = StagedOutput(format: .mp3, url: box.dir.appending(path: ".zivlet-ghost.mp3"), byteCount: 1)
        #expect(throws: JobError.publishFailed(errno: ENOENT)) { try publisher.publish(ghost, for: request) }
    }
}

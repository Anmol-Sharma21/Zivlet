import Darwin
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// G-16: the staged file lives inside a private 0700 directory that Zivlet creates exclusively in the destination, so
/// nobody else can add, swap or link entries between the checks and the writes (closes D-M3-26's window).
@Suite("Private staging directory (G-16)")
struct PrivateStagingTests {
    let publisher = Publisher()

    @Test func theStagedFileIsInsideAPrivateDirectoryOwnedByThisUser() throws {
        let box = try Sandbox()
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let workspace = try publisher.claimStaging(for: request)
        let folder = workspace.stagedFile.deletingLastPathComponent()
        #expect(folder.lastPathComponent == ".zivlet-\(request.id)")
        #expect(folder.deletingLastPathComponent().path == box.dir.path)
        var info = stat()
        try #require(lstat(folder.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o777 == 0o700 && info.st_uid == getuid())
        #expect(FileManager.default.fileExists(atPath: workspace.stagedFile.path))
    }

    @Test func aSymlinkWaitingAtTheStagingNameMakesTheClaimFail() throws {
        let box = try Sandbox()
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let elsewhere = box.dir.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: box.dir.appending(path: ".zivlet-\(request.id)"), withDestinationURL: elsewhere)
        #expect(throws: JobError.publishFailed(errno: EEXIST)) { try publisher.claimStaging(for: request) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    /// A worker killed during an ImageIO write leaves the encoder's temporary sibling `.staged.<ext>-XXXXXX` (seen in
    /// the worker smoke run); discarding must remove it, or the retry cannot claim the same staging folder again.
    @Test func discardingRemovesAnEncodersLeftoverTemporaryAndTheRetryCanClaimAgain() throws {
        let box = try Sandbox()
        let request = try box.request("photo.heic", .heic, to: .png)
        let workspace = try publisher.claimStaging(for: request)
        let folder = workspace.stagedFile.deletingLastPathComponent()
        try Data("partial".utf8).write(to: folder.appending(path: ".staged.png-rynv0d"))
        try publisher.discard(workspace)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(throws: Never.self) { try publisher.discard(try publisher.claimStaging(for: request)) }
    }

    @Test func discardingLeavesAnythingElseInTheFolderAlone() throws {
        let box = try Sandbox()
        let request = try box.request("photo.heic", .heic, to: .png)
        let workspace = try publisher.claimStaging(for: request)
        let other = workspace.stagedFile.deletingLastPathComponent().appending(path: "not-ours.txt")
        try Data("x".utf8).write(to: other)
        #expect(throws: JobError.self) { try publisher.discard(workspace) }
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func publishingLeavesNoStagingEntry() throws {
        let box = try Sandbox()
        try box.file("photo.heic")
        let request = try box.request("photo.heic", .heic, to: .jpg)
        _ = try publisher.publish(try box.staged(request, publisher: publisher), for: request)
        #expect(box.listing == ["photo.heic", "photo.jpg"])
    }

    @Test func discardingRemovesTheFileAndTheDirectory() throws {
        let box = try Sandbox()
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let workspace = try publisher.claimStaging(for: request)
        try publisher.discard(workspace)
        try publisher.discard(workspace)
        #expect(box.listing.isEmpty)
    }

    @Test(arguments: [true, false])
    func theReaperRemovesALeftoverStagingDirectory(fileStillThere: Bool) throws {
        let box = try Sandbox()
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let workspace = try publisher.claimStaging(for: request)
        if !fileStillThere { try FileManager.default.removeItem(at: workspace.stagedFile) }
        let store = JobRecordStore(directory: box.dir.appending(path: "Jobs", directoryHint: .isDirectory))
        try store.write(JobRecord(job: request.id, ownerPID: 999_999, stagedFile: workspace.stagedFile))
        let report = OrphanReaper(store: store, processes: DeadProcesses(), currentPID: 1).reap()
        #expect(report.removedFiles == 1)
        #expect(box.listing == ["Jobs"])
    }

    @Test func ownershipAndModeAreRequiredWhereTheVolumeHasThem() {
        var info = stat()
        info.st_mode = S_IFDIR | 0o700
        info.st_uid = geteuid()
        #expect(StagingDirectory.isPrivate(info, volumeIgnoresOwnership: false))
        info.st_mode = S_IFDIR | 0o755
        #expect(!StagingDirectory.isPrivate(info, volumeIgnoresOwnership: false))
        #expect(StagingDirectory.isPrivate(info, volumeIgnoresOwnership: true))
        info.st_mode = S_IFLNK | 0o700
        #expect(!StagingDirectory.isPrivate(info, volumeIgnoresOwnership: true))
        info.st_mode = S_IFDIR | 0o700
        info.st_uid = geteuid() + 1
        #expect(!StagingDirectory.isPrivate(info, volumeIgnoresOwnership: false))
    }
}

/// Every owner is gone; nothing runs.
struct DeadProcesses: ProcessInspecting {
    func isAlive(_ pid: Int32) -> Bool { false }
    func executablePath(_ pid: Int32) -> String? { nil }
    func startTime(_ pid: Int32) -> UInt64? { nil }
    func killGroup(_ pgid: Int32) {}
}

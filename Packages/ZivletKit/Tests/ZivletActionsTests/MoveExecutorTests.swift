import Foundation
import TestSupport
import Testing
import ZivletRuntime

@testable import ZivletActions

/// Moves "trashed" items into a folder of the sandbox instead of the person's Trash.
nonisolated final class SandboxTrash: @unchecked Sendable {
    let folder: URL
    var refuses = false

    init(in dir: TempDir) throws { folder = try dir.folder("Trash") }

    func trash(_ url: URL) throws {
        if refuses { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.moveItem(at: url, to: folder.appending(path: UUID().uuidString))
    }
}

@Suite("Move executor on real files (P1-45)")
struct MoveExecutorTests {
    let dir: TempDir
    let trash: SandboxTrash

    init() throws {
        dir = try TempDir(prefix: "zivlet-move")
        trash = try SandboxTrash(in: dir)
    }

    var executor: MoveExecutor { MoveExecutor(trash: trash.trash) }

    func listing(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func aSameVolumeMoveKeepsTheInode() async throws {
        let source = try dir.file("src/a.txt", "hello")
        let destination = try dir.folder("dst")
        let before = try #require(FileStamp.read(source))
        let plan = try MoveSurvey().plan(items: [source], destination: destination)
        let report = await executor.run(plan)
        let moved = try #require(report.moved.first)
        #expect(moved.source == source.standardizedFileURL)
        #expect(moved.target.lastPathComponent == "a.txt" && moved.stamp?.fileID == before.fileID)
        #expect(!FileManager.default.fileExists(atPath: source.path) && report.failures.isEmpty)
        #expect(try String(contentsOf: moved.target, encoding: .utf8) == "hello")
    }

    @Test func aFileThatAppearsAtTheTargetAfterPlanningGetsTheNextName() async throws {
        let source = try dir.file("src/a.txt", "mine")
        let destination = try dir.folder("dst")
        let plan = try MoveSurvey().plan(items: [source], destination: destination)
        try dir.file("dst/a.txt", "intruder")
        let report = await executor.run(plan)
        #expect(report.moved.map(\.target.lastPathComponent) == ["a 2.txt"])
        #expect(try String(contentsOf: destination.appending(path: "a.txt"), encoding: .utf8) == "intruder")
    }

    @Test func aCrossVolumeFolderMoveCopiesVerifiesAndTrashesTheOriginal() async throws {
        let folder = try dir.folder("src/Album")
        try dir.file("src/Album/one.txt", "1")
        try dir.file("src/Album/inner/two.txt", "22")
        let destination = try dir.folder("dst")
        let plan = try Self.crossVolume(MoveSurvey().plan(items: [folder], destination: destination))
        let report = await executor.run(plan)
        #expect(report.failures.isEmpty && report.moved.map(\.target.lastPathComponent) == ["Album"])
        #expect(try String(contentsOf: destination.appending(path: "Album/inner/two.txt"), encoding: .utf8) == "22")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(try listing(destination) == ["Album"] && listing(trash.folder).count == 1)
    }

    @Test func aShortCopyLeavesTheSourceAndNoHiddenFile() async throws {
        let source = try dir.file("src/a.txt", "full contents")
        let destination = try dir.folder("dst")
        let short = MoveExecutor(
            copy: { _, copy throws(MoveIOError) in
                guard FileManager.default.createFile(atPath: copy.path, contents: Data("full".utf8)) else {
                    throw MoveIOError(code: EIO)
                }
            }, trash: trash.trash)
        let plan = try Self.crossVolume(MoveSurvey().plan(items: [source], destination: destination))
        let report = await short.run(plan)
        #expect(report.moved.isEmpty && report.failures == [MoveFailure(url: source, reason: .verifyFailed)])
        #expect(try String(contentsOf: source, encoding: .utf8) == "full contents")
        #expect(try listing(destination).isEmpty)
    }

    @Test func aCopyErrorIsReportedAndCleanedUp() async throws {
        let source = try dir.file("src/a.txt")
        let destination = try dir.folder("dst")
        let failing = MoveExecutor(
            copy: { _, _ throws(MoveIOError) in throw MoveIOError(code: ENOSPC) }, trash: trash.trash)
        let plan = try Self.crossVolume(MoveSurvey().plan(items: [source], destination: destination))
        let report = await failing.run(plan)
        #expect(report.failures == [MoveFailure(url: source, reason: .copyFailed(errno: ENOSPC))])
        #expect(try listing(destination).isEmpty && FileManager.default.fileExists(atPath: source.path))
    }

    @Test func anOriginalTheTrashRefusesIsKeptAndNamed() async throws {
        let source = try dir.file("src/a.txt", "x")
        let destination = try dir.folder("dst")
        trash.refuses = true
        let plan = try Self.crossVolume(MoveSurvey().plan(items: [source], destination: destination))
        let report = await executor.run(plan)
        #expect(report.moved.isEmpty && report.failures == [MoveFailure(url: source, reason: .originalKept)])
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try listing(destination) == ["a.txt"])
    }

    @Test func aRenameIntoAVanishedFolderFails() async throws {
        let source = try dir.file("src/a.txt")
        let destination = try dir.folder("dst")
        let plan = try MoveSurvey().plan(items: [source], destination: destination)
        try FileManager.default.removeItem(at: destination)
        let report = await executor.run(plan)
        #expect(report.failures == [MoveFailure(url: source, reason: .moveFailed(errno: ENOENT))])
    }

    @Test func aMoveOntoAFATDiskImage() async throws {
        let image = dir.url.appending(path: "fat.dmg")
        let mount = dir.url.appending(path: "mnt")
        guard DiskImage.attachFAT(image: image, mount: mount) else { return }  // no disk images on this runner
        defer { DiskImage.detach(mount) }
        let source = try dir.file("src/photo.jpg", String(repeating: "j", count: 4_096))
        let plan = try MoveSurvey().plan(items: [source], destination: mount)
        #expect(plan.steps.map(\.kind) == [.copyThenTrash])
        let report = await executor.run(plan)
        #expect(report.failures.isEmpty && report.moved.map(\.target.lastPathComponent) == ["photo.jpg"])
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try listing(mount).filter { !$0.hasPrefix(".") || $0.hasPrefix(".zivlet") } == ["photo.jpg"])
    }

    @Test func theSurveyReadsKindsVolumesAndNames() throws {
        let file = try dir.file("s/a.txt")
        let folder = try dir.folder("s/F")
        let package = try dir.folder("s/Tool.app")
        let destination = try dir.folder("d")
        try dir.file("d/a.txt")
        let survey = MoveSurvey()
        #expect(survey.item(file).kind == .file && survey.item(folder).kind == .folder)
        #expect(survey.item(package).kind == .package)
        #expect(survey.volume(file) != nil && survey.volume(file) == survey.volume(destination))
        #expect(survey.volume(dir.url.appending(path: "nowhere")) == nil)
        let plan = try survey.plan(items: [file, folder, package], destination: destination)
        #expect(plan.steps.map(\.target.lastPathComponent) == ["a 2.txt", "F", "Tool.app"])
        #expect(throws: MoveRefusal.notAFolder) { try survey.plan(items: [folder], destination: file) }
    }

    @Test func failureReasonsHaveUserCopy() {
        let url = URL(fileURLWithPath: "/s/a.txt")
        #expect(
            MoveFailure(url: url, reason: .verifyFailed).userMessage
                == "“a.txt” wasn't moved: the copy didn't match the original.")
        #expect(
            MoveFailure(url: url, reason: .originalKept).userMessage
                == "“a.txt” was copied, but the original couldn't be moved to the Trash.")
        #expect(
            MoveFailure(url: url, reason: .copyFailed(errno: ENOSPC)).userMessage
                == "“a.txt” couldn't be copied there (error \(ENOSPC)).")
        #expect(
            MoveFailure(url: url, reason: .moveFailed(errno: EACCES)).userMessage
                == "“a.txt” couldn't be moved there (error \(EACCES)).")
    }

    /// The same plan with every step turned into a copy, so the cross-volume path runs on one disk.
    static func crossVolume(_ plan: MovePlan) -> MovePlan {
        MovePlan(
            destination: plan.destination,
            steps: plan.steps.map {
                MoveStep(source: $0.source, target: $0.target, kind: .copyThenTrash, itemKind: $0.itemKind)
            }, skipped: plan.skipped)
    }
}

/// A small FAT disk image, the same technique as the free-space tests.
enum DiskImage {
    static func attachFAT(image: URL, mount: URL) -> Bool {
        run(["create", "-size", "16m", "-fs", "MS-DOS", "-volname", "ZIVMOVE", "-quiet", image.path])
            && run(["attach", image.path, "-nobrowse", "-quiet", "-mountpoint", mount.path])
    }

    static func detach(_ mount: URL) { _ = run(["detach", mount.path, "-force", "-quiet"]) }

    private static func run(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

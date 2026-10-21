import Foundation
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// Free space reported by a test.
struct FixedFreeSpace: FreeSpaceReading {
    let bytes: Int64?
    func freeBytes(at folder: URL) -> Int64? { bytes }
}

@Suite("Disk preflight before a job starts (P1-13, 03a §4.2, 10 §8.6)")
struct DiskPreflightTests {
    static let megabyte: Int64 = 1_024 * 1_024

    @Test(arguments: [
        (Int64(1_000) * megabyte, Int64(2_012) * megabyte, true),  // 1.5 × 1000 + 512 = 2012 MB: just enough
        (1_000 * megabyte, 2_012 * megabyte - 1, false),
        (0, 512 * megabyte, true),
        (0, 512 * megabyte - 1, false),
        (Int64.max, Int64.max, false),
    ])
    func freeSpaceMustCoverOneAndAHalfTimesTheEstimatePlusAReserve(estimate: Int64, free: Int64, passes: Bool) {
        let result = Result { () throws(JobError) in try DiskPreflight.check(estimatedBytes: estimate, freeBytes: free)
        }
        let passed = (try? result.get()) != nil
        #expect(passed == passes)
        if !passes { #expect(throws: JobError.diskFull) { try result.get() } }
    }

    @Test func anUnknownFreeSpaceDoesNotBlockTheJob() throws {
        try DiskPreflight.check(estimatedBytes: Int64.max, freeBytes: nil)
    }

    @Test func theVolumeOfARealFolderReportsFreeSpace() {
        let free = VolumeFreeSpace().freeBytes(at: FileManager.default.temporaryDirectory)
        #expect((free ?? 0) > 0)
        #expect(VolumeFreeSpace().freeBytes(at: URL(fileURLWithPath: "/nonexistent-\(UUID())")) == nil)
    }

    /// FAT32 and exFAT report 0 for important usage while plenty is free; 0 there means "cannot say".
    @Test(arguments: [
        (Int64?(5_000), Int64?(9_000), Int64?(5_000)),
        (0, 9_000, 9_000),
        (nil, 9_000, 9_000),
        (0, 0, 0),
        (0, nil, nil),
        (nil, nil, nil),
    ])
    func aZeroImportantUsageFallsBackToTheAvailableCapacity(important: Int64?, available: Int64?, free: Int64?) {
        #expect(VolumeFreeSpace.resolve(important: important, available: available) == free)
    }

    @Test func aFATVolumeReportsItsRealFreeSpace() throws {
        let box = try Sandbox()
        let image = box.dir.appending(path: "fat.dmg")
        let mount = box.dir.appending(path: "mnt")
        guard Self.hdiutil(["create", "-size", "64m", "-fs", "MS-DOS", "-volname", "SATFAT", "-quiet", image.path]),
            Self.hdiutil(["attach", image.path, "-nobrowse", "-quiet", "-mountpoint", mount.path])
        else { return }  // no disk images here (sandboxed runner): the pure fallback test above still holds
        defer { _ = Self.hdiutil(["detach", mount.path, "-force", "-quiet"]) }
        #expect((VolumeFreeSpace().freeBytes(at: mount) ?? 0) > 32 * Self.megabyte)
    }

    static func hdiutil(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The engine may write up to the free space minus the reserve, and no limit when free space is unknown.
    @Test(arguments: [(Int64?(10 * 1_024 * megabyte), Int64?(10 * 1_024 * megabyte - 512 * megabyte)), (nil, nil)])
    func theEngineGetsAnOutputByteLimit(free: Int64?, limit: Int64?) async throws {
        let box = try Sandbox()
        let seen = Mutex<Int64??>(nil)
        let engine = FakeEngine { _, context throws(JobError) in seen.withLock { $0 = .some(context.outputByteLimit) } }
        let scheduler = JobScheduler(
            engines: [engine], lanes: .standard(performanceCores: 2), records: nil, processes: SystemProcesses(),
            freeSpace: FixedFreeSpace(bytes: free), clock: { .zero })
        let request = try box.request("photo.heic", .heic, to: .jpg)
        _ = await scheduler.collect(until: await scheduler.submit([request]))
        #expect(seen.withLock { $0 } == .some(limit))
    }

    @Test func aFullDiskFailsTheJobBeforeTheEngineRunsAndLeavesNothing() async throws {
        let box = try Sandbox()
        try box.file("photo.heic", String(repeating: "x", count: 1_000))
        let prepared = Mutex(0)
        let engine = FakeEngine { _, _ throws(JobError) in prepared.withLock { $0 += 1 } }
        let scheduler = JobScheduler(
            engines: [engine], lanes: .standard(performanceCores: 2), records: nil, processes: SystemProcesses(),
            freeSpace: FixedFreeSpace(bytes: 100 * Self.megabyte), clock: { .zero })
        let request = try box.request("photo.heic", .heic, to: .jpg)
        let batch = await scheduler.submit([request])
        let states = await scheduler.collect(until: batch).states(of: request.id)
        #expect(states.last == .failed(.diskFull))
        #expect(prepared.withLock { $0 } == 0)
        #expect(box.listing == ["photo.heic"])
    }
}

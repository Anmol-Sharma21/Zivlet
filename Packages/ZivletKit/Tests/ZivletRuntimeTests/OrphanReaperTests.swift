import Darwin
import Foundation
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// A process table for the reaper: which PIDs live and run what; kills are recorded.
final class FakeProcesses: ProcessInspecting {
    let alive: Set<Int32>
    let paths: [Int32: String]
    let kills = Mutex<[Int32]>([])

    init(alive: Set<Int32> = [], paths: [Int32: String] = [:]) {
        self.alive = alive
        self.paths = paths
    }

    func isAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
    func executablePath(_ pid: Int32) -> String? { paths[pid] }
    func killGroup(_ pgid: Int32) { kills.withLock { $0.append(pgid) } }
    var killed: [Int32] { kills.withLock { $0 } }
}

@Suite("Job records and the orphan reaper (P1-32, 03a §4.8)")
struct OrphanReaperTests {
    static func store() throws -> (JobRecordStore, Sandbox) {
        let box = try Sandbox()
        return (JobRecordStore(directory: box.dir.appending(path: "Jobs")), box)
    }

    @Test func recordsRoundTripAndCanBeRemoved() throws {
        let (store, box) = try Self.store()
        let record = JobRecord(job: JobID(), ownerPID: 7, stagedFile: box.dir.appending(path: ".zivlet-x.mp4"))
        try store.write(record)
        try store.write(record.with(childPID: 9, childPath: "/opt/homebrew/bin/ffmpeg"))
        #expect(store.all() == [record.with(childPID: 9, childPath: "/opt/homebrew/bin/ffmpeg")])
        store.remove(record.job)
        store.remove(record.job)
        #expect(store.all().isEmpty)
    }

    @Test func unreadableRecordsAreDropped() throws {
        let (store, _) = try Self.store()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: store.directory.appending(path: "broken.json"))
        #expect(store.all().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).isEmpty)
    }

    @Test func staleJobsLoseTheirHelperAndTheirStagedFile() throws {
        let (store, box) = try Self.store()
        let staged = try box.file(".zivlet-dead.mp4", "partial")
        try store.write(
            JobRecord(job: JobID(), ownerPID: 100, stagedFile: staged, childPID: 200, childPath: "/x/ffmpeg"))
        let processes = FakeProcesses(alive: [200], paths: [200: "/x/ffmpeg"])
        let report = OrphanReaper(store: store, processes: processes, currentPID: 1).reap()
        #expect(report == OrphanReaper.Report(killed: 1, removedFiles: 1))
        #expect(processes.killed == [200])
        #expect(!FileManager.default.fileExists(atPath: staged.path) && store.all().isEmpty)
    }

    @Test func aRecycledPIDRunningSomethingElseIsLeftAlone() throws {
        let (store, box) = try Self.store()
        try store.write(
            JobRecord(
                job: JobID(), ownerPID: 100, stagedFile: box.dir.appending(path: ".zivlet-a"), childPID: 200,
                childPath: "/x/ffmpeg"))
        let processes = FakeProcesses(alive: [200], paths: [200: "/Applications/Mail.app/Contents/MacOS/Mail"])
        #expect(OrphanReaper(store: store, processes: processes, currentPID: 1).reap().killed == 0)
        #expect(processes.killed.isEmpty)
    }

    @Test func jobsOfAnotherLiveInstanceAreKept() throws {
        let (store, box) = try Self.store()
        let staged = try box.file(".zivlet-live.mp4")
        try store.write(JobRecord(job: JobID(), ownerPID: 100, stagedFile: staged))
        let report = OrphanReaper(store: store, processes: FakeProcesses(alive: [100]), currentPID: 1).reap()
        #expect(report == OrphanReaper.Report(killed: 0, removedFiles: 0))
        #expect(store.all().count == 1 && FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func onlyHiddenStagingFilesAreEverDeleted() throws {
        let (store, box) = try Self.store()
        let precious = try box.file("Holiday.mov")
        try store.write(JobRecord(job: JobID(), ownerPID: 100, stagedFile: precious))
        _ = OrphanReaper(store: store, processes: FakeProcesses(), currentPID: 1).reap()
        #expect(FileManager.default.fileExists(atPath: precious.path))
    }

    @Test func aLiveSleepChildIsReapedForReal() async throws {
        let (store, box) = try Self.store()
        let pid = Mutex<Int32>(0)
        let child = Task {
            try await SubprocessRunner().run(
                SubprocessRequest(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]),
                onSpawn: { spawned in pid.withLock { $0 = spawned } })
        }
        while pid.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        let sleeper = pid.withLock { $0 }
        let path = try #require(SystemProcesses().executablePath(sleeper))
        let staged = try box.file(".zivlet-sleep.mp4")
        let deadOwner = Int32.max
        try store.write(
            JobRecord(job: JobID(), ownerPID: deadOwner, stagedFile: staged, childPID: sleeper, childPath: path))
        #expect(OrphanReaper(store: store).reap() == OrphanReaper.Report(killed: 1, removedFiles: 1))
        #expect(try await child.value.termination == .signaled(SIGKILL))
        #expect(!SystemProcesses().isAlive(sleeper))
    }
}

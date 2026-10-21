import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// The process facts the reaper needs, injectable for tests.
public protocol ProcessInspecting: Sendable {
    func isAlive(_ pid: Int32) -> Bool
    func executablePath(_ pid: Int32) -> String?
    /// When the process started, in microseconds since 1970; nil when it is gone or cannot be read.
    func startTime(_ pid: Int32) -> UInt64?
    func killGroup(_ pgid: Int32)
}

public struct SystemProcesses: ProcessInspecting {
    public init() {}

    public func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    public func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func startTime(_ pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    public func killGroup(_ pgid: Int32) { killpg(pgid, SIGKILL) }
}

/// Launch-time cleanup (P1-32, 03a §4.8): for each record whose owner is gone, kill the helper's process group if
/// that PID is still the recorded process (path and start time), delete the hidden staged file and its folder, then the record.
public struct OrphanReaper: Sendable {
    public struct Report: Sendable, Equatable {
        public let killed: Int
        public let removedFiles: Int
    }

    let store: JobRecordStore
    let processes: any ProcessInspecting
    let currentPID: Int32

    public init(
        store: JobRecordStore = JobRecordStore(), processes: any ProcessInspecting = SystemProcesses(),
        currentPID: Int32 = getpid()
    ) {
        self.store = store
        self.processes = processes
        self.currentPID = currentPID
    }

    public func reap() -> Report {
        let stale = store.all().filter { $0.ownerPID == currentPID || !processes.isAlive($0.ownerPID) }
        var killed = 0
        var removed = 0
        for record in stale {
            if isStillTheHelper(record) {
                processes.killGroup(record.childPID ?? 0)
                killed += 1
            }
            if Self.removeStaging(record.stagedFile) { removed += 1 }
            store.remove(record.job)
        }
        return Report(killed: killed, removedFiles: removed)
    }

    /// PID, executable path and start time must all match: a PID reused by another process, even another ffmpeg,
    /// is left alone, and so is any record that lacks one of the three (G-11). A sandboxed helper starts as
    /// `sandbox-exec` and then executes ffmpeg or ffprobe in the same process (D-M4-19), so a record of the launcher
    /// also matches a process now running one of those helpers.
    func isStillTheHelper(_ record: JobRecord) -> Bool {
        guard let pid = record.childPID, pid > 0, let path = record.childPath, let start = record.childStart,
            processes.startTime(pid) == start, let now = processes.executablePath(pid)
        else { return false }
        guard path == HelperSandbox.launcher.path, now != path else { return now == path }
        return Self.helperNames.contains((now as NSString).lastPathComponent)
    }

    static let helperNames: Set<String> = ["ffmpeg", "ffprobe"]

    /// Only hidden staging entries are ever deleted: the file inside a `.zivlet-<job>` folder and the folder (G-16),
    /// or a hidden staged file left by an older version. True when something was removed.
    static func removeStaging(_ stagedFile: URL) -> Bool {
        guard let folder = StagingDirectory.folder(of: stagedFile) else {
            return isStagingName(stagedFile.lastPathComponent) && unlink(stagedFile.path) == 0
        }
        let removedFile = unlink(stagedFile.path) == 0
        let removedFolder = rmdir(folder.path) == 0
        return removedFile || removedFolder
    }

    static func isStagingName(_ name: String) -> Bool {
        name.hasPrefix(Publisher.stagingPrefix)
    }
}

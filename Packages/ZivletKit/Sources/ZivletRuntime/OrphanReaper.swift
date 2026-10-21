import Darwin
import Foundation
import ZivletCore

/// What a running job leaves on disk so a later launch can clean up after a crash (03a §4.8): the owning app's PID,
/// the hidden staged file, and the helper child (PID and executable path) while one runs.
public struct JobRecord: Sendable, Codable, Equatable {
    public let job: JobID
    public let ownerPID: Int32
    public let stagedFile: URL
    public let childPID: Int32?
    public let childPath: String?

    public init(job: JobID, ownerPID: Int32, stagedFile: URL, childPID: Int32? = nil, childPath: String? = nil) {
        self.job = job
        self.ownerPID = ownerPID
        self.stagedFile = stagedFile
        self.childPID = childPID
        self.childPath = childPath
    }

    public func with(childPID: Int32, childPath: String?) -> JobRecord {
        JobRecord(job: job, ownerPID: ownerPID, stagedFile: stagedFile, childPID: childPID, childPath: childPath)
    }
}

/// `<Caches>/app.zivlet.Zivlet/Jobs/<job id>.json`, one file per running job.
public struct JobRecordStore: Sendable {
    public let directory: URL

    public init(directory: URL = JobRecordStore.defaultDirectory()) { self.directory = directory }

    public static func defaultDirectory() -> URL {
        URL.cachesDirectory.appending(path: "app.zivlet.Zivlet/Jobs", directoryHint: .isDirectory)
    }

    public func write(_ record: JobRecord) throws(JobError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: file(record.job), options: .atomic)
        } catch {
            throw .internalInvariant("job record not written: \(error.localizedDescription)")
        }
    }

    /// Removing a record that is already gone is fine.
    public func remove(_ job: JobID) {
        unlink(file(job).path)
    }

    /// Every readable record; unreadable files are deleted (they can never be acted on).
    public func all() -> [JobRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            let url = directory.appending(path: name)
            guard let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(JobRecord.self, from: data)
            else {
                unlink(url.path)
                return nil
            }
            return record
        }
    }

    private func file(_ job: JobID) -> URL { directory.appending(path: "\(job).json", directoryHint: .notDirectory) }
}

/// The process facts the reaper needs, injectable for tests.
public protocol ProcessInspecting: Sendable {
    func isAlive(_ pid: Int32) -> Bool
    func executablePath(_ pid: Int32) -> String?
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

    public func killGroup(_ pgid: Int32) { killpg(pgid, SIGKILL) }
}

/// Launch-time cleanup (P1-32, 03a §4.8): for each record whose owner is gone, kill the helper's process group if
/// that PID still runs the recorded executable, delete the hidden staged file, then the record.
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
            if let pid = record.childPID, let path = record.childPath, processes.executablePath(pid) == path {
                processes.killGroup(pid)
                killed += 1
            }
            if Self.isStagingName(record.stagedFile.lastPathComponent),
                unlink(record.stagedFile.path) == 0
            {
                removed += 1
            }
            store.remove(record.job)
        }
        return Report(killed: killed, removedFiles: removed)
    }

    /// Only hidden staging files are ever deleted.
    static func isStagingName(_ name: String) -> Bool {
        name.hasPrefix(Publisher.stagingPrefix)
    }
}

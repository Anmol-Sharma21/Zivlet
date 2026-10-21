import Darwin
import Foundation
import ZivletCore

/// What a running job leaves on disk so a later launch can clean up after a crash (03a §4.8): the owning app's PID,
/// the hidden staged file, and the helper child while one runs: its PID, executable path and start time
/// (microseconds since 1970), so a recycled PID is never mistaken for it (G-11).
public struct JobRecord: Sendable, Codable, Equatable {
    public let job: JobID
    public let ownerPID: Int32
    public let stagedFile: URL
    public let childPID: Int32?
    public let childPath: String?
    public let childStart: UInt64?

    public init(
        job: JobID, ownerPID: Int32, stagedFile: URL, childPID: Int32? = nil, childPath: String? = nil,
        childStart: UInt64? = nil
    ) {
        self.job = job
        self.ownerPID = ownerPID
        self.stagedFile = stagedFile
        self.childPID = childPID
        self.childPath = childPath
        self.childStart = childStart
    }

    public func with(childPID: Int32, childPath: String?, childStart: UInt64?) -> JobRecord {
        JobRecord(
            job: job, ownerPID: ownerPID, stagedFile: stagedFile, childPID: childPID, childPath: childPath,
            childStart: childStart)
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

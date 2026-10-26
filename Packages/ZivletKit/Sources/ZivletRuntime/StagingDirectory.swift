import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// The private folder a job stages in (G-16): `<destination>/.zivlet-<job>`, made with `mkdir(0700)` (which fails
/// if anything, a symlink included, already has the name) and checked on the opened descriptor before the staged
/// file is created inside it with `openat(O_EXCL | O_NOFOLLOW)`. Another user cannot add or swap entries in a 0700
/// folder this user owns, so the window between the staged-file checks and the writers' opens is closed. Volumes
/// that ignore ownership (exFAT, some SMB mounts) report every file as the current user's: there is no other user to
/// keep out, so only the type is checked there.
enum StagingDirectory {
    static let mode: mode_t = 0o700
    static let stagedName = JobWorkspace.stagedFileStem

    /// Creates the folder and an empty staged file `staged.<ext>` in it.
    static func claim(in destination: URL, job: JobID, ext: String) throws(JobError) -> URL {
        let folder = destination.appending(
            path: "\(Publisher.stagingPrefix)\(job)", directoryHint: .isDirectory)
        guard mkdir(folder.path, mode) == 0 else { throw Publisher.claimError(errno, folder: destination) }
        let dirFD = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw .verificationFailed(StagedFile.replacedMessage) }
        defer { close(dirFD) }
        try checkPrivate(dirFD)
        let name = "\(stagedName).\(ext)"
        let fd = openat(dirFD, name, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let error = Publisher.claimError(errno, folder: destination)
            rmdir(folder.path)
            throw error
        }
        close(fd)
        return folder.appending(path: name, directoryHint: .notDirectory)
    }

    /// The opened folder must still be the private one `mkdir` made; a swapped one is left alone.
    private static func checkPrivate(_ dirFD: Int32) throws(JobError) {
        var info = stat()
        var volume = statfs()
        guard fstat(dirFD, &info) == 0, fstatfs(dirFD, &volume) == 0 else { throw .publishFailed(errno: errno) }
        let ignoresOwnership = volume.f_flags & UInt32(MNT_IGNORE_OWNERSHIP) != 0
        guard isPrivate(info, volumeIgnoresOwnership: ignoresOwnership) else {
            throw .verificationFailed(StagedFile.replacedMessage)
        }
    }

    /// A directory; where the volume keeps ownership, also owned by this user and closed to everyone else.
    static func isPrivate(_ info: stat, volumeIgnoresOwnership: Bool) -> Bool {
        guard info.st_mode & S_IFMT == S_IFDIR else { return false }
        if volumeIgnoresOwnership { return true }
        return info.st_uid == geteuid() && info.st_mode & 0o077 == 0
    }

    /// The staging folder of a staged file, when it is one (by name, so nothing else is ever removed).
    static func folder(of stagedFile: URL) -> URL? {
        let folder = stagedFile.deletingLastPathComponent()
        return folder.lastPathComponent.hasPrefix(Publisher.stagingPrefix) ? folder : nil
    }

    /// Removes the staged file (if still there) and then its folder. Already gone is fine.
    static func remove(_ stagedFile: URL) throws(JobError) {
        guard unlink(stagedFile.path) == 0 || errno == ENOENT else { throw .publishFailed(errno: errno) }
        try removeFolder(of: stagedFile)
    }

    /// Removes the (empty) staging folder after its file was published or deleted. Already gone is fine.
    static func removeFolder(of stagedFile: URL) throws(JobError) {
        guard let folder = folder(of: stagedFile) else { return }
        guard rmdir(folder.path) == 0 || errno == ENOENT else { throw .publishFailed(errno: errno) }
    }
}

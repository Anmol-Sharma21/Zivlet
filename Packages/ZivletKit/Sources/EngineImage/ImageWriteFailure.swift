import Darwin
import Foundation
import ZivletCore

/// An encoder or Quartz write that failed. ImageIO reports no errno, so a nearly full volume is read as `diskFull`;
/// anything else is a write failure, never blamed on the input.
enum ImageWriteFailure {
    static let message = "The converted image could not be written."
    /// Below this much free space a failed write is taken to be the disk filling up.
    static let nearlyFullBytes: Int64 = 64 << 20

    static func error(at staged: URL) -> JobError {
        error(freeBytes: freeBytes(of: staged.deletingLastPathComponent()))
    }

    static func error(freeBytes: Int64?) -> JobError {
        guard let freeBytes, freeBytes < nearlyFullBytes else { return .writeFailed(message) }
        return .diskFull
    }

    /// `statfs` free blocks for unprivileged writers; nil when the folder cannot be read.
    static func freeBytes(of folder: URL) -> Int64? {
        var info = statfs()
        guard statfs(folder.path, &info) == 0 else { return nil }
        return Int64(info.f_bavail) * Int64(info.f_bsize)
    }

    /// A finished file must exist and hold bytes.
    static func isWritten(_ url: URL) -> Bool {
        var info = stat()
        return stat(url.path, &info) == 0 && info.st_size > 0
    }
}

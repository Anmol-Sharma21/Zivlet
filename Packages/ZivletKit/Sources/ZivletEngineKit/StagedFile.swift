import Darwin
import Foundation
import ZivletCore

/// Checks that the staged path still names Zivlet's own file before a writer opens it and before it is published
/// (03a §4.3, 10 §8.6). Anyone who can write in the destination folder could swap `.zivlet-<job>.<ext>` for a
/// symlink (ffmpeg and Quartz follow it and would overwrite its target) or for a link to, or a copy of, their own
/// file (which would then be published under the converted name). A regular file owned by this user with one link
/// passes; a missing file passes too, since the writer then only creates a new one.
public enum StagedFile {
    public static let replacedMessage = "The staged output was replaced by another file."

    public static func check(_ url: URL) throws(JobError) {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return }
        let isRegular = info.st_mode & S_IFMT == S_IFREG
        guard isRegular, info.st_uid == geteuid(), info.st_nlink == 1 else {
            throw .verificationFailed(replacedMessage)
        }
    }
}

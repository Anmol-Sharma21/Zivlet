import Darwin
import Foundation
import ZivletCore
import ZivletEngineKit

/// Writes encoded bytes to the staged file without following a symlink planted there (03a §4.3): `StagedFile.check`
/// first, then `open` with `O_NOFOLLOW`. A full volume is `diskFull`; anything else a write failure.
enum StagedBytes {
    static func write(_ data: Data, to url: URL) throws(JobError) {
        try StagedFile.check(url)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o666)
        guard fd >= 0 else { throw failure(errno, url) }
        defer { close(fd) }
        let failed: Int32? = data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress?.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return errno
                }
                offset += written
            }
            return nil
        }
        if let failed { throw failure(failed, url) }
    }

    static func failure(_ code: Int32, _ url: URL) -> JobError {
        switch code {
        case ELOOP: .verificationFailed(StagedFile.replacedMessage)
        case ENOSPC, EDQUOT: .diskFull
        default: ImageWriteFailure.error(at: url)
        }
    }
}

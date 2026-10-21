import Darwin
import Foundation
import ZivletCore

/// The size and first bytes of a dropped file, read without following a symlink and without blocking on a FIFO
/// (P1-62). The type check runs on the opened descriptor, so the file cannot be swapped between check and read.
struct InputHeader: Sendable, Equatable {
    let byteCount: Int64
    let bytes: Data

    static func read(_ url: URL, length: Int = ContentSniffer.headerLength) throws(JobError) -> InputHeader {
        guard url.isFileURL else { throw .unsupportedInput(.notAFile) }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw errno == ELOOP ? .unsupportedInput(.notAFile) : .unsupportedInput(.unreadable)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw .unsupportedInput(.unreadable) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw .unsupportedInput(.notAFile) }
        var buffer = [UInt8](repeating: 0, count: length)
        let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, length) }
        guard count >= 0 else { throw .unsupportedInput(.unreadable) }
        return InputHeader(byteCount: Int64(info.st_size), bytes: Data(buffer.prefix(count)))
    }
}

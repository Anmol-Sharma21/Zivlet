import Foundation
import ZivletRuntime

/// An item that now lives at `target`; `stamp` (read right after the move) lets Undo check it is unchanged.
nonisolated public struct MovedItem: Sendable, Equatable {
    public let source: URL
    public let target: URL
    public let stamp: FileStamp?
}

/// One item that was not moved, and why.
nonisolated public struct MoveFailure: Sendable, Equatable {
    public enum Reason: Error, Sendable, Equatable {
        /// The same-volume rename failed with `errno` (other than a name collision).
        case moveFailed(errno: Int32)
        /// Copying to the other volume failed with `errno`; nothing is left behind there.
        case copyFailed(errno: Int32)
        /// The copy's size or item count differed from the original; the copy was removed.
        case verifyFailed
        /// The copy is in place but the Trash refused the original, so both exist.
        case originalKept
        /// Every candidate name in the destination was taken by the time of the move.
        case noFreeName
    }

    public let url: URL
    public let reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }

    /// One line for the result card, naming the item.
    public var userMessage: String {
        let name = "“\(url.lastPathComponent)”"
        switch reason {
        case .moveFailed(let code): return "\(name) couldn't be moved there (error \(code))."
        case .copyFailed(let code): return "\(name) couldn't be copied there (error \(code))."
        case .verifyFailed: return "\(name) wasn't moved: the copy didn't match the original."
        case .originalKept: return "\(name) was copied, but the original couldn't be moved to the Trash."
        case .noFreeName: return "Every name for \(name) is already taken in that folder."
        }
    }
}

nonisolated public struct MoveReport: Sendable, Equatable {
    public let moved: [MovedItem]
    public let failures: [MoveFailure]
    public let skipped: [MoveSkip]
}

/// A POSIX error from a file operation.
nonisolated public struct MoveIOError: Error, Sendable, Equatable {
    public let code: Int32
    public init(code: Int32) { self.code = code }
}

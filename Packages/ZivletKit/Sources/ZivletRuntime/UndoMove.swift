import Darwin
import Foundation

/// One item a Move put elsewhere: where it was, where it is, and its stamp right after the move (03a §4.7).
public struct UndoMove: Sendable, Equatable, Codable {
    public let original: URL
    public let moved: URL
    public let fileID: UInt64
    public let byteCount: Int64
    public let modified: Date

    public init(original: URL, moved: URL, stamp: FileStamp) {
        self.original = original
        self.moved = moved
        fileID = stamp.fileID
        byteCount = stamp.byteCount
        modified = stamp.modified
    }

    var stamp: FileStamp { FileStamp(fileID: fileID, byteCount: byteCount, modified: modified) }
}

/// What undoing a Move will do: items still exactly as moved, whose old place is free, go back.
public struct MoveUndoPlan: Sendable, Equatable {
    public let restore: [UndoMove]
    public let skipped: [UndoSkip]
}

public enum MoveUndoPlanner {
    /// Pure: `stamp` reads the moved item now (nil = missing); `occupied` says whether its old place is taken.
    public static func plan(_ moves: [UndoMove], stamp: (URL) -> FileStamp?, occupied: (URL) -> Bool)
        -> MoveUndoPlan
    {
        var restore: [UndoMove] = []
        var skipped: [UndoSkip] = []
        for move in moves {
            switch stamp(move.moved) {
            case .none: skipped.append(UndoSkip(url: move.moved, reason: .missing))
            case .some(let current) where current != move.stamp:
                skipped.append(UndoSkip(url: move.moved, reason: .changed))
            case .some where occupied(move.original):
                skipped.append(UndoSkip(url: move.moved, reason: .originalTaken))
            case .some: restore.append(move)
            }
        }
        return MoveUndoPlan(restore: restore, skipped: skipped)
    }

    /// Anything at the path, a dangling symlink included.
    public static func isOccupied(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}

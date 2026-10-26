import Foundation

/// One copy that Copy to… made (P2-142, D-M5b-13): where it is and its stamp right after it was made. Undo puts it in
/// the Trash only while the stamp is unchanged; the original was never touched.
public struct UndoCopy: Sendable, Equatable, Codable {
    public let copy: URL
    public let fileID: UInt64
    public let byteCount: Int64
    public let modified: Date

    public init(copy: URL, stamp: FileStamp) {
        self.copy = copy
        fileID = stamp.fileID
        byteCount = stamp.byteCount
        modified = stamp.modified
    }

    var stamp: FileStamp { FileStamp(fileID: fileID, byteCount: byteCount, modified: modified) }
}

extension UndoPlanner {
    /// Pure, as for outputs: copies still exactly as made go to the Trash; changed or missing ones are listed.
    public static func plan(copies: [UndoCopy], stamp: (URL) -> FileStamp?) -> UndoPlan {
        var trash: [URL] = []
        var skipped: [UndoSkip] = []
        for copy in copies {
            switch stamp(copy.copy) {
            case .none: skipped.append(UndoSkip(url: copy.copy, reason: .missing))
            case .some(let current) where current == copy.stamp: trash.append(copy.copy)
            case .some: skipped.append(UndoSkip(url: copy.copy, reason: .changed))
            }
        }
        return UndoPlan(trash: trash, skipped: skipped)
    }
}

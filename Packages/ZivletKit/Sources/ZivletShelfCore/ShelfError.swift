/// Why a Drop Box value was refused (P2-141). One case per rule; `userMessage` is the sentence Zivlet shows, in
/// its own words and without file names or paths (those stay out of logs and toasts).
public enum ShelfError: Error, Equatable, Sendable {
    /// A bookmark that is empty or larger than `ShelfItem.maxBookmarkBytes`.
    case badBookmark
    /// A last known path that does not start at the root.
    case relativePath(String)
    /// A path that is too long or holds a NUL byte.
    case invalidPath
    /// A name that is empty, too long, or holds a control character or a slash.
    case invalidName
    /// A size below zero.
    case negativeSize
    /// An owned copy's path that would leave the box's own folder.
    case ownedPathOutsideBox
    /// A file identity without a volume.
    case invalidIdentity
    /// A new box past `ShelfLibrary.maxBoxes`.
    case tooManyBoxes
    /// Something that is not a file URL was offered as a file.
    case notAFileURL
    /// The system could not make a bookmark for the file (it is gone, or unreadable).
    case bookmarkFailed
    /// An owned copy could not be moved to the Trash.
    case trashFailed
    /// The box's own folder could not be made.
    case storageFailed

    public var userMessage: String {
        switch self {
        case .badBookmark: "Zivlet lost track of where this item is."
        case .relativePath: "This item's saved location is incomplete."
        case .invalidPath: "This item's saved location is too long or damaged."
        case .invalidName: "This item's name can't be used."
        case .negativeSize: "This item's size couldn't be read."
        case .ownedPathOutsideBox: "This kept copy is outside the box's folder."
        case .invalidIdentity: "This item couldn't be told apart from others."
        case .tooManyBoxes: "You have 8 boxes. Clear one to start another."
        case .notAFileURL: "Only files and folders can go in a box."
        case .bookmarkFailed: "Zivlet couldn't keep track of this file."
        case .trashFailed: "Zivlet couldn't move this kept copy to the Trash."
        case .storageFailed: "Zivlet couldn't make room to keep this copy."
        }
    }
}

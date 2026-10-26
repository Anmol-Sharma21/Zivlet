/// Every SF Symbol the Drop Box and the tray draw (19c §3.5), by meaning. One meaning per symbol, as the wheel's.
nonisolated public enum BoxSymbols {
    public static let box = "tray.full"
    public static let empty = "tray"
    public static let dropHere = "tray.and.arrow.down.fill"
    public static let share = "square.and.arrow.up"
    public static let airDrop = "airplayaudio"
    public static let copy = "doc.on.doc"
    public static let moveTo = "folder"
    public static let copyTo = "plus.rectangle.on.folder"
    public static let copyPaths = "link"
    public static let trash = "trash"
    public static let remove = "minus.circle"
    public static let clear = "xmark.bin"
    public static let more = "ellipsis.circle"
    public static let grid = "square.grid.2x2"
    public static let list = "list.bullet"
    public static let openPanel = "arrow.up.left.and.arrow.down.right"
    public static let locate = "magnifyingglass"
    public static let quickLook = "eye"
    public static let removeMissing = remove
    public static let badgeMissing = "questionmark"
    public static let badgeTrash = trash
    public static let badgeOffline = "externaldrive.badge.xmark"
    public static let undo = "arrow.uturn.backward"
    public static let cancel = "stop.circle"
    public static let close = "xmark.circle"
    public static let saved = "checkmark.circle.fill"
    public static let failed = "exclamationmark.triangle.fill"

    /// Each name once, for the test that every one resolves.
    public static let all: [String] = [
        box, empty, dropHere, share, airDrop, copy, moveTo, copyTo, copyPaths, trash, remove, clear, more, grid, list,
        openPanel, locate, quickLook, badgeMissing, badgeOffline, undo, cancel, close, saved, failed,
    ]
}

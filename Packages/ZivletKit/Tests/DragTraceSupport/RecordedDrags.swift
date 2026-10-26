import Foundation

/// Where the owner's recorded drags are (OS-M5b-1): the folder named by `ZIVLET_DRAG_TRACES`, or nil when it is not
/// set or empty (CI and ordinary runs), in which case the recorded replays are skipped and say so.
public enum RecordedDrags {
    public static var folder: URL? {
        guard let path = ProcessInfo.processInfo.environment["ZIVLET_DRAG_TRACES"], !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}

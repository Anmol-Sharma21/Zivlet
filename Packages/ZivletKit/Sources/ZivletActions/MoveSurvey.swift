import Darwin
import Foundation

/// Reads what the planner needs from disk: each item's kind, volumes (`st_dev`) and the names already in the
/// destination. Symlinks are moved as links, so items are read without following them. Paths are compared as
/// given (Finder and the open panel both hand over real paths); the kernel refuses a folder renamed into itself
/// even if a symlinked spelling slipped past the planner.
nonisolated public struct MoveSurvey: Sendable {
    public init() {}

    public func plan(items: [URL], destination: URL, mode: MovePlan.Mode = .move) throws(MoveRefusal) -> MovePlan {
        let folder = destination.standardizedFileURL
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let existing = Set(names.map { folder.appending(path: $0).path })
        return try MovePlanner.plan(
            items: items.map(item), destination: item(folder), volumes: volume, existing: existing, mode: mode)
    }

    public func item(_ url: URL) -> MoveItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true, values?.isDirectory == true else {
            return MoveItem(url: url, kind: .file)
        }
        return MoveItem(url: url, kind: values?.isPackage == true ? .package : .folder)
    }

    func volume(_ url: URL) -> VolumeID? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return VolumeID(UInt64(bitPattern: Int64(info.st_dev)))
    }
}

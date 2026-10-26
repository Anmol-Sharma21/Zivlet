import Foundation

/// Bookmarks through Foundation (D-M5b-2). Never security-scoped: the prototype showed a security-scoped bookmark
/// of a Downloads file raising a folder prompt, while these options made only silent checks.
public struct SystemBookmarks: BookmarkMaking, BookmarkResolving {
    public static let creationOptions: URL.BookmarkCreationOptions = [.withoutImplicitSecurityScope]
    public static let resolutionOptions: URL.BookmarkResolutionOptions = [
        .withoutUI, .withoutMounting, .withoutImplicitStartAccessing,
    ]

    public init() {}

    public func bookmark(for url: URL) throws(ShelfError) -> Data {
        guard url.isFileURL else { throw .notAFileURL }
        let data: Data
        do {
            data = try url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil)
        } catch {
            throw .bookmarkFailed
        }
        guard data.count <= ShelfItem.maxBookmarkBytes else { throw .badBookmark }
        return data
    }

    public func identity(of url: URL) -> FileIdentity? {
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .fileIdentifierKey]),
            let volume = values.volumeUUIDString, let fileID = values.fileIdentifier
        else { return nil }
        return FileIdentity(volumeUUID: volume, fileID: fileID)
    }

    public func size(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileSizeKey]),
            values.isDirectory != true, let size = values.totalFileSize
        else { return nil }
        return Int64(size)
    }

    public func resolve(_ bookmark: Data) -> Resolution {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark, options: Self.resolutionOptions, relativeTo: nil,
                bookmarkDataIsStale: &stale)
            return .resolved(path: url.path, stale: stale)
        } catch {
            let values = URL.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey], fromBookmarkData: bookmark)
            return .failed(
                code: (error as NSError).code, storedVolumePath: values?.volume?.path,
                storedVolumeName: values?.volumeName)
        }
    }

    /// Whether a volume path is mounted now.
    public static func isMounted(_ volumePath: String) -> Bool {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        return volumes.contains { $0.path == volumePath }
    }
}

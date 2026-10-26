import Foundation

/// Makes what a box keeps about a file (D-M5b-2): a bookmark that is never security-scoped, the file's identity
/// for de-dup and its size. The system implementation is `SystemBookmarks`; tests use fakes.
public protocol BookmarkMaking: Sendable {
    func bookmark(for url: URL) throws(ShelfError) -> Data
    func identity(of url: URL) -> FileIdentity?
    /// Nil for folders and unreadable sizes.
    func size(of url: URL) -> Int64?
}

/// Finds a file again from its bookmark, without UI, without mounting and without starting access (D-M5b-2).
public protocol BookmarkResolving: Sendable {
    func resolve(_ bookmark: Data) -> Resolution
}

/// What resolving one bookmark gave: a path (stale when the file moved or was renamed, so the bookmark should be
/// made again), or the error code with the volume the bookmark remembers, which tells "not connected" apart from
/// "deleted" (both give error 4).
public enum Resolution: Sendable, Equatable {
    case resolved(path: String, stale: Bool)
    case failed(code: Int, storedVolumePath: String?, storedVolumeName: String?)
}

extension ShelfItem {
    /// A reference to the file at `url`, added at `now`. Only file URLs; the name is the file's own.
    public static func referencing(_ url: URL, using maker: any BookmarkMaking, now: Date) throws(ShelfError)
        -> ShelfItem
    {
        guard url.isFileURL else { throw .notAFileURL }
        let file = url.standardizedFileURL
        return try ShelfItem(
            bookmark: maker.bookmark(for: file), lastKnownPath: file.path, displayName: file.lastPathComponent,
            byteCount: maker.size(of: file), addedAt: now, identity: maker.identity(of: file))
    }
}

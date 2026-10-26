import Foundation

@testable import ZivletShelfCore

/// Scripted bookmark ports: `resolutions` maps a bookmark to its answer; the maker returns the path's bytes, or
/// fails for the paths in `failing`.
struct FakeBookmarks: BookmarkMaking, BookmarkResolving {
    var resolutions: [Data: Resolution] = [:]
    var failing: Set<String> = []

    func bookmark(for url: URL) throws(ShelfError) -> Data {
        guard !failing.contains(url.path) else { throw .bookmarkFailed }
        return Data(url.path.utf8)
    }

    func identity(of url: URL) -> FileIdentity? { nil }
    func size(of url: URL) -> Int64? { 42 }

    func resolve(_ bookmark: Data) -> Resolution {
        resolutions[bookmark] ?? .failed(code: 4, storedVolumePath: nil, storedVolumeName: nil)
    }
}

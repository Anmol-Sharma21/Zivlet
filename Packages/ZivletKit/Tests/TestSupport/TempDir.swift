import Foundation

/// A fresh folder under the temporary directory, removed when the value goes away.
public final class TempDir: @unchecked Sendable {
    public let url: URL

    public init(prefix: String = "zivlet-test") throws {
        url = FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Writes `contents` to `name` (intermediate folders are created) and returns its URL.
    @discardableResult
    public func file(_ name: String, _ contents: String = "data") throws -> URL {
        let file = url.appending(path: name, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }

    @discardableResult
    public func folder(_ name: String) throws -> URL {
        let folder = url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

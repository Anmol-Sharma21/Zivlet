import Foundation

/// Where the box keeps its own copies (P2-141): only content that has no file of its own (file promises, text and
/// image clippings) is copied, into `<root>/<box id>/`. Names are made safe and never leave the box's folder.
public struct OwnedStorage: Sendable {
    static let folderMode = 0o700
    /// "Clipping 2.txt" … "Clipping 9999.txt", then the name is refused.
    static let maxNumber = 9_999

    public let root: URL

    public init(root: URL) { self.root = root }

    /// `~/Library/Application Support/Zivlet/Box/`.
    public static func standard() -> OwnedStorage {
        OwnedStorage(root: URL.applicationSupportDirectory.appending(path: "Zivlet/Box", directoryHint: .isDirectory))
    }

    public func folder(for box: UUID) -> URL {
        root.appending(path: box.uuidString, directoryHint: .isDirectory)
    }

    /// The box's folder, made (0700) when missing: where received file promises land.
    public func makeFolder(for box: UUID) throws(ShelfError) -> URL {
        let folder = folder(for: box)
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: Self.folderMode])
        } catch {
            throw .storageFailed
        }
        return folder
    }

    /// A free file URL for `name` in the box's folder (made, 0700, when missing): the name made safe, then
    /// "name 2.ext", "name 3.ext" … on a clash. The file itself is not created.
    public func reserve(name: String, in box: UUID) throws(ShelfError) -> URL {
        guard let safe = Self.sanitized(name) else { throw .invalidName }
        let folder = try makeFolder(for: box)
        for number in 1...Self.maxNumber {
            let candidate = Self.numbered(safe, number)
            guard ShelfItem.isValidName(candidate) else { break }
            let url = folder.appending(path: candidate, directoryHint: .notDirectory)
            guard url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else {
                throw .ownedPathOutsideBox
            }
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw .invalidName
    }

    /// The path an owned item stores, relative to the root; nil for a URL outside it.
    public func relativePath(of url: URL) -> String? {
        let prefix = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    public func url(forRelativePath relative: String) throws(ShelfError) -> URL {
        guard ShelfItem.isInsideFolder(relative) else { throw .ownedPathOutsideBox }
        return root.appending(path: relative, directoryHint: .notDirectory)
    }

    /// Every entry `<box id>/<name>` under the root whose relative path is not in `keeping`: copies no item points
    /// at (a crash inside Clear's undo window, a drop the box did not take). Hidden files and anything outside a
    /// box folder are left alone; nothing below a box folder's own entries is looked at.
    public func strays(keeping: Set<String>) -> [URL] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { UUID(uuidString: $0.lastPathComponent) != nil }.flatMap { folder in
            let entries =
                (try? manager.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            return entries.filter { !keeping.contains("\(folder.lastPathComponent)/\($0.lastPathComponent)") }
        }.sorted { $0.path < $1.path }
    }

    /// Removes the box's folder when it holds nothing (`rmdir`, which refuses a folder with anything in it).
    public func removeFolderIfEmpty(for box: UUID) {
        _ = rmdir(folder(for: box).path)
    }

    /// Bytes of the owned copies of one box; 0 when it has none.
    public func bytes(in box: UUID) -> Int64 { Self.bytes(under: folder(for: box)) }

    /// Bytes of every owned copy, for the 2 GB warning (OWN-APP-3).
    public func allBytes() -> Int64 { Self.bytes(under: root) }

    private static func bytes(under folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return 0
        }
        return files.compactMap { $0 as? URL }.reduce(0) { total, url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return total }
            return total + Int64(values?.totalFileSize ?? 0)
        }
    }

    /// One file name: slashes and colons become hyphens, control characters go, and leading dots and spaces are
    /// dropped (no hidden files, no `..`). Nil when nothing usable is left.
    static func sanitized(_ name: String) -> String? {
        let replaced = String(
            name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map {
                $0 == "/" || $0 == ":" ? "-" : Character($0)
            })
        let trimmed = replaced.drop { $0 == "." || $0 == " " }.trimmingCharacters(in: .whitespaces)
        return ShelfItem.isValidName(trimmed) ? trimmed : nil
    }

    /// "a.txt" → "a 2.txt"; number 1 is the name itself.
    static func numbered(_ name: String, _ number: Int) -> String {
        guard number > 1 else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return ext.isEmpty || base.isEmpty ? "\(name) \(number)" : "\(base) \(number).\(ext)"
    }
}

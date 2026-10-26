import Foundation

/// One file in a box (P2-141, 17e §2.3). Immutable and valid by construction: every initializer, the decoder and
/// every edit run the same rules, so a value read from `boxes.json` is as safe as one made from a drop.
public struct ShelfItem: Sendable, Equatable, Codable, Identifiable {
    /// A reference points at the person's own file; an owned copy lives in the box's folder (promises, clippings).
    public enum Ownership: Sendable, Equatable, Codable {
        case reference
        /// Relative to the owned-storage root, never leaving it.
        case owned(relativePath: String)
    }

    public static let maxBookmarkBytes = 16_384
    public static let maxPathBytes = 4_096
    public static let maxNameBytes = 255

    public let id: UUID
    public let bookmark: Data
    public let lastKnownPath: String
    public let displayName: String
    public let byteCount: Int64?
    public let addedAt: Date
    public let ownership: Ownership
    public let identity: FileIdentity?

    public init(
        id: UUID = UUID(), bookmark: Data, lastKnownPath: String, displayName: String, byteCount: Int64?,
        addedAt: Date, ownership: Ownership = .reference, identity: FileIdentity? = nil
    ) throws(ShelfError) {
        try Self.validate(bookmark: bookmark, path: lastKnownPath, name: displayName, size: byteCount)
        try Self.validate(ownership: ownership, identity: identity)
        self.id = id
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.displayName = displayName
        self.byteCount = byteCount
        self.addedAt = addedAt
        self.ownership = ownership
        self.identity = identity
    }

    public var isOwned: Bool { ownership != .reference }

    /// The same item at a new place (a stale bookmark was refreshed, Move to…, Locate…). The name follows the file and
    /// the identity is the new file's, so de-dup keeps working after a move across volumes. An owned copy stays owned
    /// only while it is still inside `storage`: once elsewhere it is the person's file, so the box never trashes it,
    /// nor whatever later takes its old name in the box's folder.
    public func relocated(
        to path: String, bookmark: Data, identity: FileIdentity?, storage: OwnedStorage
    ) throws(ShelfError) -> ShelfItem {
        let name = (path as NSString).lastPathComponent
        return try ShelfItem(
            id: id, bookmark: bookmark, lastKnownPath: path, displayName: name.isEmpty ? displayName : name,
            byteCount: byteCount, addedAt: addedAt, ownership: Self.ownership(ownership, at: path, in: storage),
            identity: identity)
    }

    /// A reference stays one; an owned copy keeps its ownership, at its new relative path, only inside `storage`.
    static func ownership(_ old: Ownership, at path: String, in storage: OwnedStorage) -> Ownership {
        guard case .owned = old, let relative = storage.relativePath(of: URL(filePath: path)), isInsideFolder(relative)
        else { return .reference }
        return .owned(relativePath: relative)
    }

    /// The same item with a newly read size; nil for folders or when the size is unknown.
    public func withSize(_ size: Int64?) throws(ShelfError) -> ShelfItem {
        try ShelfItem(
            id: id, bookmark: bookmark, lastKnownPath: lastKnownPath, displayName: displayName, byteCount: size,
            addedAt: addedAt, ownership: ownership, identity: identity)
    }

    private enum CodingKeys: String, CodingKey {
        case id, bookmark, lastKnownPath, displayName, byteCount, addedAt, ownership, identity
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(UUID.self, forKey: .id), bookmark: c.decode(Data.self, forKey: .bookmark),
            lastKnownPath: c.decode(String.self, forKey: .lastKnownPath),
            displayName: c.decode(String.self, forKey: .displayName),
            byteCount: c.decodeIfPresent(Int64.self, forKey: .byteCount),
            addedAt: c.decode(Date.self, forKey: .addedAt), ownership: c.decode(Ownership.self, forKey: .ownership),
            identity: c.decodeIfPresent(FileIdentity.self, forKey: .identity))
    }
}

extension ShelfItem {
    static func validate(bookmark: Data, path: String, name: String, size: Int64?) throws(ShelfError) {
        guard (1...maxBookmarkBytes).contains(bookmark.count) else { throw .badBookmark }
        guard path.hasPrefix("/") else { throw .relativePath(path) }
        guard path.utf8.count <= maxPathBytes, !path.utf8.contains(0) else { throw .invalidPath }
        guard isValidName(name) else { throw .invalidName }
        if let size, size < 0 { throw .negativeSize }
    }

    static func validate(ownership: Ownership, identity: FileIdentity?) throws(ShelfError) {
        if case .owned(let relative) = ownership, !isInsideFolder(relative) { throw .ownedPathOutsideBox }
        if let identity, !identity.isValid { throw .invalidIdentity }
    }

    /// 1…255 UTF-8 bytes, no control characters, no slash: a single file name as Finder shows it.
    static func isValidName(_ name: String) -> Bool {
        (1...maxNameBytes).contains(name.utf8.count) && !name.contains("/")
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Exactly `<box id>/<file name>`: a UUID folder and one valid name that is not `.` or `..`. Anything else
    /// (the storage root, a whole box folder, a nested path) would let a damaged `boxes.json` steer what the box
    /// trashes.
    static func isInsideFolder(_ relative: String) -> Bool {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, UUID(uuidString: String(parts[0])) != nil else { return false }
        let name = String(parts[1])
        return name != "." && name != ".." && isValidName(name)
    }
}

extension ShelfItem {
    /// The item at `path` with a bookmark and identity made there by `maker`.
    func relocated(to path: String, using maker: any BookmarkMaking, storage: OwnedStorage) throws(ShelfError)
        -> ShelfItem
    {
        let url = URL(filePath: path)
        return try relocated(
            to: path, bookmark: maker.bookmark(for: url), identity: maker.identity(of: url), storage: storage)
    }
}

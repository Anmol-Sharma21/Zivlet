import Foundation
import ZivletCore

/// One box (P2-141, 17e §2.3): its items in order, where its panel sits and how it shows them. Immutable: every
/// edit returns a new box and leaves the receiver as it was.
public struct Shelf: Sendable, Equatable, Codable, Identifiable {
    public enum ViewMode: String, Sendable, Codable, CaseIterable {
        case grid, list
    }

    public static let maxNameBytes = 255

    public let id: UUID
    public let name: String
    public let items: [ShelfItem]
    public let frame: Rect2D?
    public let dock: DockEdge?
    public let viewMode: ViewMode
    public let updatedAt: Date
    /// How the panel was shown when it was last saved, so a relaunch restores it (P2-55 §9.5). Schema 1 files
    /// without the field, or with a value this Zivlet does not know, read as hidden.
    public let shown: BoxPresentation.Base

    public init(
        id: UUID = UUID(), name: String, items: [ShelfItem] = [], frame: Rect2D? = nil, dock: DockEdge? = nil,
        viewMode: ViewMode = .grid, updatedAt: Date, shown: BoxPresentation.Base = .hidden
    ) throws(ShelfError) {
        guard Self.isValidName(name) else { throw .invalidName }
        self.id = id
        self.name = name
        self.items = items
        self.frame = frame
        self.dock = dock
        self.viewMode = viewMode
        self.updatedAt = updatedAt
        self.shown = shown
    }

    /// A box without items. `now` defaults to the distant past so that a box nobody used is never the most recent.
    public static func empty(name: String, id: UUID = UUID(), now: Date = .distantPast) throws(ShelfError) -> Shelf {
        try Shelf(id: id, name: name, updatedAt: now)
    }

    /// 1…255 UTF-8 bytes without control characters.
    static func isValidName(_ name: String) -> Bool {
        (1...maxNameBytes).contains(name.utf8.count)
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, frame, dock, viewMode, updatedAt, shown
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(UUID.self, forKey: .id), name: c.decode(String.self, forKey: .name),
            items: c.decode([ShelfItem].self, forKey: .items), frame: c.decodeIfPresent(Rect2D.self, forKey: .frame),
            dock: c.decodeIfPresent(DockEdge.self, forKey: .dock), viewMode: c.decode(ViewMode.self, forKey: .viewMode),
            updatedAt: c.decode(Date.self, forKey: .updatedAt),
            shown: BoxPresentation.Base(stored: try? c.decodeIfPresent(String.self, forKey: .shown)))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(frame, forKey: .frame)
        try c.encodeIfPresent(dock, forKey: .dock)
        try c.encode(viewMode, forKey: .viewMode)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(shown.stored, forKey: .shown)
    }
}

// MARK: - Edits

extension Shelf {
    /// The same box with other items, place or time; the one place that copies every field.
    func with(
        items: [ShelfItem]? = nil, frame: Rect2D?? = nil, dock: DockEdge?? = nil, viewMode: ViewMode? = nil,
        updatedAt: Date? = nil, shown: BoxPresentation.Base? = nil
    ) -> Shelf {
        Shelf(
            unchecked: id, name: name, items: items ?? self.items, frame: frame ?? self.frame, dock: dock ?? self.dock,
            viewMode: viewMode ?? self.viewMode, updatedAt: updatedAt ?? self.updatedAt, shown: shown ?? self.shown)
    }

    /// For edits of a value that was already validated; the name does not change here.
    private init(
        unchecked id: UUID, name: String, items: [ShelfItem], frame: Rect2D?, dock: DockEdge?, viewMode: ViewMode,
        updatedAt: Date, shown: BoxPresentation.Base
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.frame = frame
        self.dock = dock
        self.viewMode = viewMode
        self.updatedAt = updatedAt
        self.shown = shown
    }

    /// Adds `incoming` in order, skipping files already in the box (or earlier in `incoming`) and every item past
    /// `cap`. De-dup: the same item id, the same `FileIdentity` when both items have one, else the same standardised
    /// path.
    public func adding(_ incoming: [ShelfItem], cap: Int) -> (Shelf, AddReport) {
        var index = DuplicateIndex(items)
        var kept = items
        var ids = Set(items.map(\.id))
        var added: [UUID] = []
        var duplicates: [String] = []
        var overCap: [String] = []
        for item in incoming {
            if ids.contains(item.id) || index.contains(item) {
                duplicates.append(item.displayName)
            } else if kept.count >= cap {
                overCap.append(item.displayName)
            } else {
                index.insert(item)
                ids.insert(item.id)
                kept.append(item)
                added.append(item.id)
            }
        }
        return (with(items: kept), AddReport(added: added, duplicates: duplicates, overCap: overCap))
    }

    public func removing(_ ids: Set<UUID>) -> Shelf {
        with(items: items.filter { !ids.contains($0.id) })
    }

    /// The items named in `ids` first, in that order, then every other item in its old order. Unknown ids are
    /// ignored.
    public func reordering(_ ids: [UUID]) -> Shelf {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let front = ids.uniqued().compactMap { byID[$0] }
        let named = Set(front.map(\.id))
        return with(items: front + items.filter { !named.contains($0.id) })
    }

    /// The items in `moves` (id → new path) at their new places, with bookmarks and identities read there (P2-142
    /// Move to…, Locate…), and the ids whose bookmark could not be made: those keep their old reference and are found
    /// again on the next show. An owned copy moved out of `storage` becomes a reference.
    public func relocating(
        _ moves: [UUID: String], using maker: any BookmarkMaking, storage: OwnedStorage
    ) -> (Shelf, failed: Set<UUID>) {
        var failed: Set<UUID> = []
        let next = items.map { item in
            guard let path = moves[item.id] else { return item }
            do {
                return try item.relocated(to: path, using: maker, storage: storage)
            } catch {
                failed.insert(item.id)
                return item
            }
        }
        return (with(items: next), failed)
    }

    public func renamed(_ name: String) throws(ShelfError) -> Shelf {
        try Shelf(
            id: id, name: name, items: items, frame: frame, dock: dock, viewMode: viewMode, updatedAt: updatedAt,
            shown: shown)
    }

    public func placed(frame: Rect2D?, dock: DockEdge?) -> Shelf { with(frame: .some(frame), dock: .some(dock)) }

    public func showing(_ mode: ViewMode) -> Shelf { with(viewMode: mode) }

    /// The same box with its panel last shown as `base`.
    public func presented(_ base: BoxPresentation.Base) -> Shelf { with(shown: base) }

    public func touched(at now: Date) -> Shelf { with(updatedAt: now) }

    public var totals: ShelfTotals {
        let known = items.compactMap(\.byteCount)
        let owned = items.filter(\.isOwned).compactMap(\.byteCount)
        return ShelfTotals(
            count: items.count, bytes: known.reduce(0, +), ownedBytes: owned.reduce(0, +),
            unknownSizes: items.count - known.count)
    }
}

/// The files a box already holds, for de-dup in one pass.
private struct DuplicateIndex {
    private var identities: Set<FileIdentity> = []
    private var paths: [String: [FileIdentity?]] = [:]

    init(_ items: [ShelfItem]) { items.forEach { insert($0) } }

    func contains(_ item: ShelfItem) -> Bool {
        if let identity = item.identity, identities.contains(identity) { return true }
        // At the same path, two items are one file unless both have identities (which then differ).
        return paths[Self.key(item), default: []].contains { $0 == nil || item.identity == nil }
    }

    mutating func insert(_ item: ShelfItem) {
        if let identity = item.identity { identities.insert(identity) }
        paths[Self.key(item), default: []].append(item.identity)
    }

    private static func key(_ item: ShelfItem) -> String {
        URL(filePath: item.lastKnownPath, directoryHint: .notDirectory).standardized.path
    }
}

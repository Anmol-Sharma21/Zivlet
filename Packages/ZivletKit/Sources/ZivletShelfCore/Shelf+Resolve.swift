import Foundation

/// A box after resolving its bookmarks (D-M5b-3): every item's status, the box with stale items refreshed (new
/// bookmark and path), and the items whose refresh failed (they keep their old bookmark and are tried again next
/// time).
public struct ResolvedShelf: Sendable, Equatable {
    public let shelf: Shelf
    public let statuses: [UUID: ItemStatus]
    public let refreshFailed: Set<UUID>

    /// Items that cannot be used now: in the Trash, offline or missing.
    public var missingCount: Int { statuses.values.filter { !$0.isAvailable }.count }
}

extension Shelf {
    /// This box with the items of `resolved`, keeping its own name, frame and state as they are now: a resolution
    /// made off the main thread lands on the box as it has become meanwhile.
    public func withItems(of resolved: Shelf) -> Shelf { with(items: resolved.items) }

    /// Resolves every item, lazily called when the box or tray is shown, never at launch (P2-141). A stale owned copy
    /// found outside `storage` becomes a reference.
    public func resolving(
        with resolver: any BookmarkResolving, maker: any BookmarkMaking, isMounted: (String) -> Bool,
        storage: OwnedStorage
    ) -> ResolvedShelf {
        var statuses: [UUID: ItemStatus] = [:]
        var failed: Set<UUID> = []
        let refreshed = items.map { item in
            let resolution = resolver.resolve(item.bookmark)
            let status = ItemStatus.from(resolution, isMounted: isMounted)
            statuses[item.id] = status
            guard case .resolved(let path, true) = resolution, status.isAvailable else { return item }
            do {
                return try item.relocated(to: path, using: maker, storage: storage)
            } catch {
                failed.insert(item.id)
                return item
            }
        }
        return ResolvedShelf(shelf: with(items: refreshed), statuses: statuses, refreshFailed: failed)
    }
}

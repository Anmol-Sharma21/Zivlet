import Foundation
import ZivletShelfCore

/// Resolves a box's bookmarks off the main thread (G-M5b-8): the shelf's own pure resolution, run on a concurrent
/// thread with the ports it needs, all of them `Sendable`.
nonisolated struct BoxResolver: Sendable {
    let resolver: any BookmarkResolving
    let maker: any BookmarkMaking
    let isMounted: @Sendable (String) -> Bool
    let storage: OwnedStorage

    init(ports: BoxPorts) {
        resolver = ports.resolver
        maker = ports.maker
        isMounted = ports.isMounted
        storage = ports.storage
    }

    @concurrent func resolve(_ shelf: Shelf) async -> ResolvedShelf {
        shelf.resolving(with: resolver, maker: maker, isMounted: isMounted, storage: storage)
    }
}

extension BoxController {
    /// Starts resolving `shelf`, replacing any resolution still running.
    func resolve(_ shelf: Shelf) {
        resolving?.cancel()
        let resolver = BoxResolver(ports: ports)
        resolving = Task { [weak self] in
            let resolved = await resolver.resolve(shelf)
            guard !Task.isCancelled else { return }
            self?.applyResolution(resolved, of: shelf)
        }
    }

    /// Takes a finished resolution when it is still about the shown box and its items are the ones resolved; a box
    /// whose items changed meanwhile is resolved again, so an item removed meanwhile never comes back.
    func applyResolution(_ resolved: ResolvedShelf, of asked: Shelf) {
        guard resolvedBox == asked.id, let now = library.boxes.first(where: { $0.id == asked.id }) else { return }
        guard now.items == asked.items else { return resolve(now) }
        statuses = resolved.statuses
        Self.logResolution(resolved)
        if resolved.shelf.items != asked.items {
            library = library.replacing(now.withItems(of: resolved.shelf))
            save()
        }
        apply(.itemsChanged(count: now.items.count, missing: resolved.missingCount))
        requestVisibleThumbnails()
        onChange()
    }

    /// Thumbnails asked for before the statuses arrived were skipped (no known path yet): the cells on screen and
    /// the tray's strip ask again. Cached ones and items no longer visible cost nothing.
    func requestVisibleThumbnails() {
        for id in onScreen { requestThumbnail(id, size: .cell) }
        guard trayRedraw != nil else { return }
        for item in BoxCompactView.strip(viewModel.items) { requestThumbnail(item.id, size: .tray) }
    }
}

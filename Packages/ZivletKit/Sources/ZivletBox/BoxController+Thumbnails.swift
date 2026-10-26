import AppKit
import ZivletShelfCore

/// Thumbnails (D-M5b-14, 19c D-BL11): only the cells on screen ask for one, the cache is the one place images live
/// (its 400-entry bound holds), and every thumbnail that arrives in one turn costs one redraw.
extension BoxController {
    /// A cell came on screen or left it. Leaving cancels its request; coming back asks again.
    public func itemShown(_ id: UUID, _ shown: Bool) {
        if shown { onScreen.insert(id) } else { onScreen.remove(id) }
        thumbnails.setVisible(onScreen, size: .cell)
        if shown { requestThumbnail(id, size: .cell) }
    }

    /// Asks Quick Look for a present item's thumbnail at `size`, unless the cache has it.
    func requestThumbnail(_ id: UUID, size: ThumbnailSize) {
        guard thumbnails.cached(id, size: size) == nil, case .present(let path) = statuses[id] else { return }
        let url = URL(filePath: path)
        Task { [weak self] in
            guard let self, await thumbnails.thumbnail(for: id, url: url, size: size) != nil else { return }
            thumbnailArrived()
        }
    }

    /// One redraw on the next turn for every arrival before it: the panel when it shows, and the tray's strip.
    func thumbnailArrived() {
        guard thumbnailRedraw == nil else { return }
        thumbnailRedraw = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            thumbnailRedraw = nil
            if panel.isVisible { render() }
            trayRedraw?()
        }
    }

    /// The image a view draws for an item: its cell thumbnail, else the icon for its type.
    func image(for item: BoxItemModel) -> NSImage {
        thumbnails.cached(item.id, size: .cell) ?? thumbnails.placeholder(forName: item.name)
    }
}

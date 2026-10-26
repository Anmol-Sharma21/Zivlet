import AppKit
import ZivletActions
import ZivletShelfCore

/// The box behind the notch tray (P2-143, NB7): the compact view's model, drops at the notch into the current box,
/// their Undo, and the panel opened from the tray. The tray resolves the box when it opens, as the panel does, so its
/// strip can be dragged out and shows badges, and it asks for its own 40 pt thumbnails.
extension BoxController: TrayBox {
    /// The compact view's model: the tray's thumbnails where they arrived, else the cell's, else the type icon.
    public var trayModel: BoxViewModel {
        let model = viewModel
        let images = Dictionary(
            model.items.map { item in
                (item.id, thumbnails.cached(item.id, size: .tray) ?? model.images[item.id] ?? NSImage())
            }, uniquingKeysWith: { first, _ in first })
        return model.with(images: images)
    }

    public var trayCount: Int { current?.items.count ?? 0 }

    public var trayBytes: Int64 { current?.totals.bytes ?? 0 }

    /// The tray opened its compact view: resolve the box (again, when the panel is not showing it, so statuses are
    /// fresh) and ask for the strip's thumbnails; `redraw` runs when one arrives.
    public func prepareTray(redraw: @escaping () -> Void) {
        if !panel.isVisible { resolvedBox = nil }
        resolveIfNeeded()
        trayRedraw = redraw
        let strip = BoxCompactView.strip(viewModel.items).map(\.id)
        thumbnails.setVisible(Set(strip), size: .tray)
        for id in strip { requestThumbnail(id, size: .tray) }
    }

    /// The same intake as the panel's drop (B7), into the current box (OWN-APP-1), inside `performDragOperation`.
    public func addDrop(_ pasteboard: NSPasteboard) async -> TrayAdded { await intakeDrop(pasteboard) }

    /// Exactly the items one tray drop added leave the current box; owned copies of them go to the Trash.
    public func undoAdd(_ ids: [UUID]) {
        guard let shelf = current else { return }
        let chosen = shelf.items.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        remove(chosen, from: shelf)
    }
}

import AppKit
import ZivletShelfCore

/// The box behind the notch tray (P2-143, NB7): the compact view's model, drops at the notch into the current box,
/// their Undo, and the panel opened from the tray.
extension BoxController: TrayBox {
    public var trayModel: BoxViewModel { viewModel }

    /// The same intake as the panel's drop (B7), into the current box (OWN-APP-1), inside `performDragOperation`.
    public func addDrop(_ pasteboard: NSPasteboard) async -> TrayAdded {
        let result = await intake.receive(from: pasteboard, box: library.current?.id ?? UUID())
        return adding(result, newBox: false)
    }

    /// Exactly the items one tray drop added leave the current box; owned copies of them go to the Trash.
    public func undoAdd(_ ids: [UUID]) {
        guard let shelf = current else { return }
        let chosen = shelf.items.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        remove(chosen, from: shelf)
    }
}

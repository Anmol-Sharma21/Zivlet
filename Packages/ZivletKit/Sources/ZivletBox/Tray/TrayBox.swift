import AppKit

/// The box behind the notch tray (P2-143, design/19 §8): what the tray shows and what it asks the box to do.
/// `BoxController` is the real one; the tray's tests use a fake.
public protocol TrayBox: AnyObject {
    /// The current box as the compact view draws it: items, totals, thumbnails.
    var trayModel: BoxViewModel { get }
    /// A drop at the notch into the current box, inside `performDragOperation` (OWN-APP-1).
    func addDrop(_ pasteboard: NSPasteboard) async -> TrayAdded
    /// Undo on the "Added 3" toast: exactly the items that drop added leave the box.
    func undoAdd(_ ids: [UUID])
    /// "Open Drop Box": the full panel, where `anchor` says.
    func showPanel(_ anchor: BoxAnchor)
    /// A button in the compact view (Share, Open Drop Box) or a drag out of its strip.
    func press(_ press: BoxPress)
}

/// What a drop at the notch did: the outcome for the toast and the ids Undo removes.
public struct TrayAdded: Sendable, Equatable {
    public let outcome: AddOutcome
    public let ids: [UUID]

    public init(outcome: AddOutcome, ids: [UUID]) {
        self.outcome = outcome
        self.ids = ids
    }
}

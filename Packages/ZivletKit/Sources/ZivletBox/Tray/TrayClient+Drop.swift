import AppKit
import ZivletNotch
import ZivletNotchCore

/// A drop at the notch (NB7, OWN-APP-1): the same intake as the panel, into the current box, then "Added 3" with Undo
/// or the reason nothing was added, then back to rest. Before the drop only the drag's types and item count are read
/// (D-M5b-4).
extension TrayClient: IslandDropHandling {
    public var dragTypes: [NSPasteboard.PasteboardType] { BoxDropView.types }

    public func draggingEntered(_ info: any NSDraggingInfo, display: UInt32) -> NSDragOperation {
        update(info, display: display)
    }

    public func draggingUpdated(_ info: any NSDraggingInfo, display: UInt32) -> NSDragOperation {
        update(info, display: display)
    }

    /// The pointer left the drop target's window; the proximity rule decides when the drop target closes.
    public func draggingExited(display: UInt32) {}

    /// Inside `performDragOperation`: promises must be received now, so the work starts at once.
    public func performDrop(_ info: any NSDraggingInfo, display: UInt32) -> Bool {
        guard dropTarget?.display == display else { return false }
        let pasteboard = info.draggingPasteboard
        dropTarget = nil
        dropTask = Task.immediate { @MainActor [weak self] in
            guard let self else { return }
            self.show(await self.box.addDrop(pasteboard), on: display)
        }
        return true
    }

    /// Undo on the toast: exactly the items that drop added leave the box; the tray goes back to rest.
    func undoLastDrop() {
        guard let toast = lastToast, !toast.undoIDs.isEmpty else { return }
        endToast()
        box.undoAdd(toast.undoIDs)
        boxChanged()
    }

    /// A drag out of the compact view's strip holds the island until it ends (D-N13).
    func stripDrag(_ began: Bool, display: UInt32) {
        if began { hosts.dragBegan(on: display) } else { hosts.dragEnded(on: display) }
    }

    func startLinger() {
        guard let toast = lastToast, !heldDisplays.contains(toast.display) else { return }
        toastTask?.cancel()
        let duration = toast.undoIDs.isEmpty ? Timing.toast : Timing.undoToast
        toastTask = Task { @MainActor [weak self] in
            await self?.linger(duration)
            guard let self, !Task.isCancelled, self.lastToast == toast else { return }
            self.endToast()
            self.rest()
        }
    }

    private func update(_ info: any NSDraggingInfo, display: UInt32) -> NSDragOperation {
        guard let target = dropTarget, target.display == display else { return [] }
        let count = info.draggingPasteboard.pasteboardItems?.count ?? target.count
        if count != target.count {
            dropTarget = (display, count)
            hosts.contentChanged(on: display)
        }
        return .copy
    }

    private func show(_ added: TrayAdded, on display: UInt32) {
        let outcome = added.outcome
        let toast: TrayToastModel
        if let text = outcome.toast {
            toast = TrayToastModel(
                display: display, text: text, spoken: BoxSpeech.added(outcome.added), failed: false,
                undoIDs: added.ids)
        } else {
            let reason = outcome.failure ?? IntakeResult.nothingUsable
            toast = TrayToastModel(display: display, text: reason, spoken: reason, failed: true, undoIDs: [])
        }
        lastToast = toast
        hosts.request(
            IslandRequest(client: .tray, display: display, resting: .toast, hoverSurface: .expanded), from: .tray)
        hosts.contentChanged(on: display)
        hosts.announce(toast.spoken, highPriority: toast.failed)
        startLinger()
        boxChanged()
    }

    private func endToast() {
        toastTask?.cancel()
        toastTask = nil
        lastToast = nil
    }
}

/// A drop's result at the notch (19c §4.2): "Added 3" with Undo, or the refusal with the triangle.
struct TrayToastModel: Equatable {
    let display: UInt32
    let text: String
    let spoken: String
    let failed: Bool
    /// The items Undo removes; empty when there is nothing to undo.
    let undoIDs: [UUID]
}

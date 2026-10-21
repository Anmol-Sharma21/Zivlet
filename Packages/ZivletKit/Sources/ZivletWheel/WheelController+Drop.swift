import AppKit
import ZivletCore
import ZivletWheelCore
import os

// Drop protocol (03a §2.5): hit-test on every update, negotiate a non-destructive operation, re-read the URLs at
// drop and require them to equal the probed set, then hand a typed selection to the delegate.
extension WheelController: WheelDropHandling {
    func dragEntered(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation {
        isPointerInsideWheel(true)
        return dragUpdated(at: point, offered: offered)
    }

    func dragUpdated(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation {
        guard let model = store.model else { return [] }
        let centre = WheelGeometry.standard.panelSide / 2
        let hit = model.hit(Point2D(x: point.x - centre, y: point.y - centre))
        store.pointer(hit)
        let operation = DropNegotiation.operation(
            offered: DragOperations(rawValue: offered.rawValue), hit: hit, hasTarget: store.model?.dropTarget != nil)
        return NSDragOperation(rawValue: operation.rawValue)
    }

    func dragExited() {
        isPointerInsideWheel(false)
        store.pointer(.outside)
    }

    func canAcceptDrop() -> Bool { store.model?.dropTarget != nil }

    /// Returns at once; the delegate only logs and schedules UI (performDragOperation budget ≤ 1 ms).
    func performDrop(from pasteboard: NSPasteboard) -> Bool {
        let urls = DragPayloadReader.fileURLs(from: pasteboard)
        guard let payload, urls == payload.urls else {
            logger.error("Drop refused: the dragged items changed since the wheel opened")
            return false
        }
        guard let selection = store.model?.selection(urls: urls, optionHeld: isOptionHeld()) else { return false }
        store.dropAccepted()
        delegate?.wheelController(self, didSelect: selection)
        return true
    }

    func dragEnded() {
        isPointerInsideWheel(false)
        onDragEnded()
    }
}

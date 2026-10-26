import AppKit
import ZivletNotchCore

/// The island panel's content view as a drag destination (D-M5b-7): it forwards AppKit's destination calls to the
/// handler the host gives it, and refuses everything when there is none. Registration is the host's decision.
extension IslandTrackingView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandler().map { $0.draggingEntered(sender, display: dropDisplay) } ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandler().map { $0.draggingUpdated(sender, display: dropDisplay) } ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropHandler()?.draggingExited(display: dropDisplay)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { dropHandler() != nil }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropHandler()?.performDrop(sender, display: dropDisplay) ?? false
    }
}

extension IslandHost {
    /// The client's drag types are registered only while its drop target is the applied surface and the wheel is
    /// not showing (D-M5b-7, D-M5b-8); otherwise none are.
    func updateDragRegistration() {
        guard surface == .dropTarget, !dragsBlocked, let handler = tracking.dropHandler(),
            !handler.dragTypes.isEmpty
        else {
            if !tracking.registeredDraggedTypes.isEmpty { tracking.unregisterDraggedTypes() }
            return
        }
        if Set(tracking.registeredDraggedTypes) != Set(handler.dragTypes) {
            tracking.registerForDraggedTypes(handler.dragTypes)
        }
    }
}

import AppKit

/// A dragging session's info over a private pasteboard, for the drop view tests (prototype (a)'s seam). Only the
/// pasteboard and the operation mask carry meaning.
final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(pasteboard: NSPasteboard) {
        draggingPasteboard = pasteboard
        numberOfValidItemsForDrop = pasteboard.pasteboardItems?.count ?? 0
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .generic] }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}

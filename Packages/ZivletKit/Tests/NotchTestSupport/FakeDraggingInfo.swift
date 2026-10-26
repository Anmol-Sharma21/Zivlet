import AppKit

/// A dragging session's info over a private pasteboard, for the drop tests of the Drop Box panel and the island's
/// tray (prototype (a)'s seam). Only the pasteboard and the operation mask carry meaning.
@MainActor
public final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    public let draggingPasteboard: NSPasteboard
    public var draggingFormation: NSDraggingFormation = .default
    public var animatesToDestination = false
    public var numberOfValidItemsForDrop = 0
    public var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    public init(pasteboard: NSPasteboard) {
        draggingPasteboard = pasteboard
        numberOfValidItemsForDrop = pasteboard.pasteboardItems?.count ?? 0
    }

    public var draggingDestinationWindow: NSWindow? { nil }
    public var draggingSourceOperationMask: NSDragOperation { [.copy, .generic] }
    public var draggingLocation: NSPoint { .zero }
    public var draggedImageLocation: NSPoint { .zero }
    public var draggedImage: NSImage? { nil }
    public var draggingSource: Any? { nil }
    public var draggingSequenceNumber: Int { 1 }

    public func slideDraggedImage(to screenPoint: NSPoint) {}

    public func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    public func resetSpringLoading() {}
}

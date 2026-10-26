import AppKit

/// A client that takes drops on the island (design/19 §8, D-M5b-7): the host registers `dragTypes` on its content
/// view only while the client's drop target is the applied surface, and hands it AppKit's dragging info. Nothing here
/// names files: what the types are and what a drop becomes is the client's business.
public protocol IslandDropHandling: AnyObject {
    var dragTypes: [NSPasteboard.PasteboardType] { get }
    func draggingEntered(_ info: any NSDraggingInfo, display: UInt32) -> NSDragOperation
    func draggingUpdated(_ info: any NSDraggingInfo, display: UInt32) -> NSDragOperation
    func draggingExited(display: UInt32)
    /// Inside `performDragOperation`, where AppKit lets a drop's file promises be received.
    func performDrop(_ info: any NSDraggingInfo, display: UInt32) -> Bool
}

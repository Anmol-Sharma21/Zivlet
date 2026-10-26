import AppKit

/// The panel's drop area (P2-55 §9.1): registered for file URLs, file promises and text or image clippings. It
/// reports the pasteboard's item count while a drag is over it and hands the pasteboard over at the drop; the
/// controller decides whether drops are accepted now (only while the drop target shows) and what they become.
public final class BoxDropView: NSView {
    public static let types: [NSPasteboard.PasteboardType] =
        [.fileURL, .string, .png, .tiff]
        + NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }

    /// A drag entered or moved: the pasteboard's item count.
    public var onEnter: (Int) -> Void = { _ in }
    public var onExit: () -> Void = {}
    /// The drop, inside `performDragOperation`, where promises may be received.
    public var onDrop: (NSPasteboard) -> Void = { _ in }
    /// Whether a drop would land now.
    public var accepts: () -> Bool = { true }

    override public init(frame: NSRect = .zero) {
        super.init(frame: frame)
        registerForDraggedTypes(Self.types)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }

    override public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }

    override public func draggingExited(_ sender: (any NSDraggingInfo)?) { onExit() }

    override public func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { accepts() }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard accepts() else { return false }
        onDrop(sender.draggingPasteboard)
        return true
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onEnter(sender.draggingPasteboard.pasteboardItems?.count ?? 0)
        return accepts() ? .copy : []
    }
}

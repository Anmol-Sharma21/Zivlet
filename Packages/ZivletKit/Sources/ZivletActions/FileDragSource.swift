import AppKit
import SwiftUI

/// Makes its content a drag source for several file URLs at once (P1-41 drag-out): SwiftUI's own drag supports one
/// item, so an AppKit view starts the session with one dragging item per file. `onDrag` hears the session begin
/// (true) and end (false), so the notch island can hold while a drag from it is in flight (D-N13); `onEnded` hears
/// how it ended (none when nothing took the files), so the Drop Box can clear items that left it. Shared by the
/// result cards and the Drop Box (D-M5b-1), so every multi-file drag out of Zivlet behaves the same.
public struct FileDragSource: NSViewRepresentable {
    public let urls: [URL]
    public let image: NSImage
    public var onDrag: (Bool) -> Void = { _ in }
    public var onEnded: (NSDragOperation) -> Void = { _ in }
    /// False when SwiftUI content draws the item and the view only carries the drag (the Drop Box's cells).
    public var drawsImage = true
    /// A press released without a drag, with its modifier keys; nil leaves clicks to AppKit.
    public var onClick: ((NSEvent.ModifierFlags) -> Void)?

    public init(
        urls: [URL], image: NSImage, drawsImage: Bool = true, onDrag: @escaping (Bool) -> Void = { _ in },
        onEnded: @escaping (NSDragOperation) -> Void = { _ in }, onClick: ((NSEvent.ModifierFlags) -> Void)? = nil
    ) {
        self.urls = urls
        self.image = image
        self.drawsImage = drawsImage
        self.onDrag = onDrag
        self.onEnded = onEnded
        self.onClick = onClick
    }

    public func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView(urls: urls, image: image)
        updateNSView(view, context: context)
        return view
    }

    public func updateNSView(_ view: DragSourceView, context: Context) {
        view.urls = urls
        view.image = image
        view.drawsImage = drawsImage
        view.onDrag = onDrag
        view.onEnded = onEnded
        view.onClick = onClick
    }
}

/// The AppKit view behind `FileDragSource`: one dragging item per URL, fanned 4 pt apart.
public final class DragSourceView: NSView, NSDraggingSource {
    public var urls: [URL]
    public var image: NSImage {
        didSet { needsDisplay = true }
    }
    public var onDrag: (Bool) -> Void = { _ in }
    public var onEnded: (NSDragOperation) -> Void = { _ in }
    public var drawsImage = true {
        didSet { needsDisplay = true }
    }
    public var onClick: ((NSEvent.ModifierFlags) -> Void)?
    private var dragged = false

    public init(urls: [URL], image: NSImage) {
        self.urls = urls
        self.image = image
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Aspect-fit, centred.
    /// A drag here moves files, never the window it sits in (the Drop Box panel moves by its background).
    override public var mouseDownCanMoveWindow: Bool { false }

    override public func draw(_ dirtyRect: NSRect) {
        let size = image.size
        guard drawsImage, size.width > 0, size.height > 0 else { return }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(
            in: CGRect(
                x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width,
                height: fitted.height))
    }

    override public func mouseDown(with event: NSEvent) {
        dragged = false
        if onClick == nil { super.mouseDown(with: event) }
    }

    override public func mouseUp(with event: NSEvent) {
        guard let onClick else { return super.mouseUp(with: event) }
        if !dragged { onClick(event.modifierFlags) }
    }

    override public func mouseDragged(with event: NSEvent) {
        dragged = true
        let items = Self.draggingItems(for: urls, frame: bounds, image: image)
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    /// One item per URL, each a file URL on the drag pasteboard (what the trigger and Finder read), fanned 4 pt apart.
    public static func draggingItems(for urls: [URL], frame: CGRect, image: NSImage? = nil) -> [NSDraggingItem] {
        urls.enumerated().map { offset, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let shift = CGFloat(offset) * 4
            item.setDraggingFrame(frame.offsetBy(dx: shift, dy: -shift), contents: image)
            return item
        }
    }

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    public func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { onDrag(true) }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation)
    {
        ended(with: operation)
    }

    /// The session ended with `operation` (empty when nothing took the files).
    public func ended(with operation: NSDragOperation) {
        onDrag(false)
        onEnded(operation)
    }
}

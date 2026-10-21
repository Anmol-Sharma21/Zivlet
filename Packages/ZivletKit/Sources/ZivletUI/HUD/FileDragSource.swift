import AppKit
import SwiftUI

/// Makes its content a drag source for several file URLs at once (P1-41 drag-out): SwiftUI's own drag supports one
/// item, so an AppKit view starts the session with one dragging item per file.
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    let image: NSImage

    func makeNSView(context: Context) -> DragSourceView { DragSourceView(urls: urls, image: image) }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.urls = urls
        view.image = image
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var urls: [URL]
    var image: NSImage {
        didSet { needsDisplay = true }
    }

    init(urls: [URL], image: NSImage) {
        self.urls = urls
        self.image = image
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Aspect-fit, centred.
    override func draw(_ dirtyRect: NSRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(
            in: CGRect(
                x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width,
                height: fitted.height))
    }

    override func mouseDragged(with event: NSEvent) {
        let items = urls.enumerated().map { offset, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let shift = CGFloat(offset) * 4
            item.setDraggingFrame(bounds.offsetBy(dx: shift, dy: -shift), contents: image)
            return item
        }
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}

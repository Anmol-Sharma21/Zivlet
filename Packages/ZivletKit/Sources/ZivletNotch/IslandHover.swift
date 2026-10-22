import AppKit

/// The panel's content view: one tracking area sized to the island's current shape, not the window (D-N6), rebuilt
/// whenever the shape or the frame changes. During a resize the transparent rest of the panel opens nothing.
final class IslandTrackingView: NSView {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    /// The shape in this view's coordinates (bottom-left origin).
    private(set) var shapeRect = CGRect.zero
    private var area: NSTrackingArea?

    func setShape(_ rect: CGRect) {
        guard rect != shapeRect else { return }
        shapeRect = rect
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: shapeRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(next)
        area = next
        super.updateTrackingAreas()
    }

    /// The tracking area's rectangle as AppKit holds it, for the tests.
    var trackingRect: CGRect? { area?.rect }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

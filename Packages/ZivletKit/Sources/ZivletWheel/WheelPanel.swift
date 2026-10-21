import AppKit
import ZivletWheelCore

/// The pre-warmed overlay window (03a §2.1, 14 §2.1): borderless and non-activating, so Finder keeps focus and its
/// drag loop; level `.popUpMenu` (101) above shelves and the Dock; on every Space including full-screen apps
/// (collection behaviour 0x159). It ignores the mouse while hidden and never becomes key in M2.
public final class WheelPanel: NSPanel {
    public init(side: Double = WheelGeometry.standard.panelSide) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// What the drop view asks its owner. Points are in the view (y up, origin at the panel's bottom-left).
protocol WheelDropHandling: AnyObject {
    func dragEntered(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation
    func dragUpdated(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation
    func dragExited()
    func canAcceptDrop() -> Bool
    func performDrop(from pasteboard: NSPasteboard) -> Bool
    func dragEnded()
}

/// The AppKit drag destination (03a §2.5, 14 §2.2). The SwiftUI hosting view inside has no drop modifiers, so
/// AppKit walks up to this view and we keep exact control of `NSDraggingInfo`.
final class WheelDropView: NSView {
    weak var handler: (any WheelDropHandling)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        handler?.dragEntered(
            at: convert(sender.draggingLocation, from: nil), offered: sender.draggingSourceOperationMask)
            ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        handler?.dragUpdated(
            at: convert(sender.draggingLocation, from: nil), offered: sender.draggingSourceOperationMask)
            ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { handler?.dragExited() }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { handler?.canAcceptDrop() ?? false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        handler?.performDrop(from: sender.draggingPasteboard) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) { handler?.dragEnded() }
}

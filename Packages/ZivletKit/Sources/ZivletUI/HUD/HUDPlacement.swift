import AppKit

/// Where a HUD panel goes: below-right of the drop point, kept 12 pt inside the visible frame of that screen
/// (nil point = centre of the main screen).
public enum HUDPlacement {
    static let margin: CGFloat = 12
    static let offset: CGFloat = 16

    public static func origin(near anchor: CGPoint?, size: NSSize) -> NSPoint? {
        let point = anchor ?? NSScreen.main.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? .zero
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return nil
        }
        let visible = screen.visibleFrame.insetBy(dx: margin, dy: margin)
        let x = min(max(point.x + offset, visible.minX), visible.maxX - size.width)
        let y = min(max(point.y - offset - size.height, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

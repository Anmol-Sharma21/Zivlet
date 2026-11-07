import CoreGraphics

/// Where the tool window opens (P2-30 "opens at the wheel location", plan 20b A2): centred on the wheel's centre and
/// kept inside the visible frame by the HUD's margin. A window larger than the frame keeps its top-left corner
/// visible, so the header and the first controls can always be reached. Pure.
public enum ToolWindowPlacement {
    public static let margin = HUDLayout.margin

    public static func frame(size: CGSize, wheelCenter: CGPoint, visibleFrame: CGRect) -> CGRect {
        let inside = visibleFrame.insetBy(dx: margin, dy: margin)
        let x =
            size.width > inside.width
            ? inside.minX : min(max(wheelCenter.x - size.width / 2, inside.minX), inside.maxX - size.width)
        let y =
            size.height > inside.height
            ? inside.maxY - size.height
            : min(max(wheelCenter.y - size.height / 2, inside.minY), inside.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// `frame` at a new `height` with its top kept, moved up just enough to stay inside the bottom margin; a window
    /// taller than the frame keeps its top visible.
    public static func grown(_ frame: CGRect, toHeight height: CGFloat, visibleFrame: CGRect) -> CGRect {
        let inside = visibleFrame.insetBy(dx: margin, dy: margin)
        let top = height > inside.height ? inside.maxY : min(max(frame.maxY, inside.minY + height), inside.maxY)
        return CGRect(x: frame.minX, y: top - height, width: frame.width, height: height)
    }
}

import ZivletCore

/// Edge docking for the Drop Box panel (17e §2.1, 19c §3.3): a panel let go within 28 pt of the left or right edge
/// of the visible frame docks there; a docked panel stays docked until pulled more than 48 pt away; a press that
/// moves less than 8 pt is a click, not a move. Pure; frames are in global points, AppKit orientation.
public enum DockSnapper {
    public static let attach = 28.0
    public static let detach = 48.0
    public static let clickSlop = 8.0

    /// The edge a panel at `frame` docks to after a move, or nil when it floats free. The nearer edge wins.
    public static func edge(for frame: Rect2D, in visible: Rect2D, current: DockEdge?) -> DockEdge? {
        let gaps: [(DockEdge, Double)] = [(.left, frame.minX - visible.minX), (.right, visible.maxX - frame.maxX)]
        let nearest = gaps.min { $0.1 < $1.1 }
        if let nearest, nearest.1 <= attach { return nearest.0 }
        guard let current, let gap = gaps.first(where: { $0.0 == current })?.1 else { return nil }
        return gap <= detach ? current : nil
    }

    /// True when the pointer moved less than `clickSlop` between press and release.
    public static func isClick(from start: Point2D, to end: Point2D) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot() < clickSlop
    }

    /// The docked tab: against its edge, centred on the panel's last vertical middle, inside the visible frame.
    public static func tabFrame(edge: DockEdge, panel: Rect2D, in visible: Rect2D, width: Double, height: Double)
        -> Rect2D
    {
        let x = edge == .left ? visible.minX : visible.maxX - width
        let y = min(max(panel.midY - height / 2, visible.minY), visible.maxY - height)
        return Rect2D(x: x, y: y, width: width, height: height)
    }
}

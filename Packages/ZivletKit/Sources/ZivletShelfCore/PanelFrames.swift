import ZivletCore

/// Where the Drop Box panel may sit (19c §3.1, §4.4). Pure; frames are in global points, AppKit orientation.
public enum PanelFrames {
    /// How far inside the visible frame a panel opened at a drop point stays, as the HUD does.
    public static let inset = 12.0
    /// The panel grows to at most this share of the visible height; the grid or list scrolls beyond it.
    public static let maxHeightShare = 0.6

    /// A saved frame on a connected display stays (pulled inside its visible frame); one on a display that is gone
    /// moves to the first display. A frame larger than the display shrinks to fit. Without displays it is kept.
    public static func clamped(_ frame: Rect2D, to visibleFrames: [Rect2D]) -> Rect2D {
        guard let first = visibleFrames.first else { return frame }
        let centre = Point2D(x: frame.midX, y: frame.midY)
        let display = visibleFrames.first { $0.contains(centre) } ?? first
        return inside(frame, display)
    }

    /// A panel of the given size with its top centred on `point`, kept `inset` inside `visible`.
    public static func placed(width: Double, height: Double, near point: Point2D, in visible: Rect2D) -> Rect2D {
        let frame = Rect2D(x: point.x - width / 2, y: point.y - height, width: width, height: height)
        let area = Rect2D(
            x: visible.minX + inset, y: visible.minY + inset, width: max(0, visible.width - 2 * inset),
            height: max(0, visible.height - 2 * inset))
        return inside(frame, area)
    }

    public static func maxHeight(in visible: Rect2D) -> Double { (visible.height * maxHeightShare).rounded(.down) }

    private static func inside(_ frame: Rect2D, _ area: Rect2D) -> Rect2D {
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - width)
        let y = min(max(frame.minY, area.minY), area.maxY - height)
        return Rect2D(x: x, y: y, width: width, height: height)
    }
}

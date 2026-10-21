import AppKit

/// Where HUD panels go (03a §4.5): below-right of the drop point, kept 12 pt inside the visible frame of the screen
/// under it; each further concurrent batch 24 pt further down-right. Pure, except `origin(near:size:)`, which reads
/// the screens.
public enum HUDLayout {
    public static let size = CGSize(width: 360, height: 108)
    static let margin: CGFloat = 12
    static let offset: CGFloat = 16
    static let cascade: CGFloat = 24

    /// `anchor` nil means the centre of `screen`.
    public static func frame(anchor: CGPoint?, index: Int, screen: CGRect, size: CGSize = size) -> CGRect {
        let point = anchor ?? CGPoint(x: screen.midX, y: screen.midY)
        let step = cascade * CGFloat(max(0, index))
        let inside = screen.insetBy(dx: margin, dy: margin)
        let x = min(max(point.x + offset + step, inside.minX), inside.maxX - size.width)
        let y = min(max(point.y - offset - step - size.height, inside.minY), inside.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// The visible frame under `point`, else the first one.
    public static func screen(for point: CGPoint?, in screens: [CGRect]) -> CGRect? {
        guard let point else { return screens.first }
        return screens.first { $0.contains(point) } ?? screens.first
    }

    /// The panel origin near `anchor` on the real screens (the action HUD's single panel).
    public static func origin(near anchor: CGPoint?, size: CGSize) -> CGPoint? {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let screen = screen(for: anchor, in: screens) else { return nil }
        return frame(anchor: anchor, index: 0, screen: screen, size: size).origin
    }
}

import ZivletCore

/// Pure frames for each surface on one display (design/19 §3.4, D-N3). On a notch display every frame hangs from the
/// top edge, centred on the housing; nothing is drawn inside the housing, so collapsed content sits in a tab below it.
/// On a display without a notch the island is a pill centred on the display, 6 pt under the menu bar. Every frame is
/// clamped inside the display frame.
public enum IslandLayout {
    public enum Metrics {
        /// How far the collapsed shape reaches past the housing on each side (the acceptance rule of §5.3).
        public static let shoulder = 6.0
        public static let tabHeight = 24.0
        public static let toastWidth = 360.0
        /// The toast's text row below the housing.
        public static let toastRow = 36.0
        public static let expandedWidth = 380.0
        public static let maxHeight = 320.0
        public static let pillCollapsed = (width: 200.0, height: 28.0)
        public static let pillToastHeight = 40.0
        public static let pillGap = 6.0
        public static let collapsedRadius = 12.0
        public static let toastRadius = 18.0
        public static let expandedRadius = 22.0
    }

    /// `contentHeight` is the measured height of the client's content (only the expanded card uses it).
    public static func frame(_ surface: IslandSurface, on display: DisplayGeometry, contentHeight: Double = 0)
        -> Rect2D
    {
        guard let housing = NotchGeometry.housing(of: display) else {
            return pillFrame(surface, on: display, contentHeight: contentHeight)
        }
        let size: (width: Double, height: Double)
        switch surface {
        case .hidden, .collapsed:
            size = (housing.width + 2 * Metrics.shoulder, housing.height + Metrics.tabHeight)
        case .toast:
            size = (Metrics.toastWidth, housing.height + Metrics.toastRow)
        case .expanded:
            size = (Metrics.expandedWidth, min(housing.height + contentHeight, Metrics.maxHeight))
        }
        return hanging(size, centredOn: housing.midX, top: display.frame.maxY, in: display.frame)
    }

    /// Where collapsed content goes: the band under the housing, never inside it; the whole pill without a notch.
    public static func tab(on display: DisplayGeometry) -> Rect2D {
        guard let housing = NotchGeometry.housing(of: display) else { return frame(.collapsed, on: display) }
        let height = Metrics.tabHeight
        return Rect2D(x: housing.minX, y: housing.minY - height, width: housing.width, height: height)
    }

    /// Content taller than the cap scrolls inside the card; the island never grows past it.
    public static func contentScrolls(contentHeight: Double, on display: DisplayGeometry) -> Bool {
        contentTopInset(on: display) + contentHeight > Metrics.maxHeight
    }

    /// The expanded card's content starts below the housing on a notch display.
    public static func contentTopInset(on display: DisplayGeometry) -> Double {
        NotchGeometry.housing(of: display)?.height ?? 0
    }

    /// The display containing the point (half-open edges), else the first; nil when there are none.
    public static func display(for point: Point2D?, in displays: [DisplayGeometry]) -> DisplayGeometry? {
        guard let point else { return displays.first }
        return displays.first { $0.frame.contains(point) } ?? displays.first
    }

    private static func pillFrame(_ surface: IslandSurface, on display: DisplayGeometry, contentHeight: Double)
        -> Rect2D
    {
        let size: (width: Double, height: Double)
        switch surface {
        case .hidden, .collapsed: size = Metrics.pillCollapsed
        case .toast: size = (Metrics.toastWidth, Metrics.pillToastHeight)
        case .expanded: size = (Metrics.expandedWidth, min(contentHeight, Metrics.maxHeight))
        }
        let top = display.visibleFrame.maxY - Metrics.pillGap
        return hanging(size, centredOn: display.frame.midX, top: top, in: display.frame)
    }

    private static func hanging(
        _ size: (width: Double, height: Double), centredOn midX: Double, top: Double, in bounds: Rect2D
    ) -> Rect2D {
        let x = clamp(midX - size.width / 2, low: bounds.minX, high: bounds.maxX - size.width)
        let y = clamp(top - size.height, low: bounds.minY, high: bounds.maxY - size.height)
        return Rect2D(x: x, y: y, width: size.width, height: size.height)
    }

    private static func clamp(_ value: Double, low: Double, high: Double) -> Double {
        guard low <= high else { return low }
        return min(max(value, low), high)
    }
}

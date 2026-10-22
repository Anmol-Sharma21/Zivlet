import ZivletCore
import ZivletNotchCore

/// Display values for the notch tests. Only `mbp14MoreSpace` was recorded on real hardware; the others are
/// constructed and named as such (design/19 §3.3). Throwing functions, because the lint rules forbid `try!`.
public enum DisplayFixtures {
    /// Recorded 2026-10-22: 14-inch MacBook Pro (M2 Pro), scaled mode 1800 × 1169 pt, macOS 27.0.
    public static func mbp14MoreSpace() throws -> DisplayGeometry {
        try DisplayGeometry(
            id: 1, frame: Rect2D(x: 0, y: 0, width: 1800, height: 1169),
            visibleFrame: Rect2D(x: 0, y: 94, width: 1800, height: 1036), safeAreaTop: 38,
            auxiliaryTopLeft: Rect2D(x: 0, y: 1131, width: 790, height: 38),
            auxiliaryTopRight: Rect2D(x: 1010, y: 1131, width: 790, height: 38), isBuiltIn: true)
    }

    /// Constructed: an external 1080p display to the left, with a 25 pt menu bar and no notch.
    public static func noNotch1080() throws -> DisplayGeometry {
        try DisplayGeometry(
            id: 2, frame: Rect2D(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: Rect2D(x: -1920, y: 0, width: 1920, height: 1055), safeAreaTop: 0,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil, isBuiltIn: false)
    }

    /// Constructed: a display that reports a safe area but no auxiliary areas (the defensive pill rule).
    public static func safeAreaWithoutAux() throws -> DisplayGeometry {
        try DisplayGeometry(
            id: 3, frame: Rect2D(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: Rect2D(x: 0, y: 0, width: 1512, height: 943), safeAreaTop: 38,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil, isBuiltIn: true)
    }

    /// Constructed: the recorded display with other auxiliary areas (overlapping ones mean no housing).
    public static func make(leftWidth: Double, rightX: Double) throws -> DisplayGeometry {
        try DisplayGeometry(
            id: 5, frame: Rect2D(x: 0, y: 0, width: 1800, height: 1169),
            visibleFrame: Rect2D(x: 0, y: 94, width: 1800, height: 1036), safeAreaTop: 38,
            auxiliaryTopLeft: Rect2D(x: 0, y: 1131, width: leftWidth, height: 38),
            auxiliaryTopRight: Rect2D(x: rightX, y: 1131, width: 1800 - rightX, height: 38), isBuiltIn: true)
    }

    /// Constructed: a 2560 × 1440 display above the recorded one, no notch.
    public static func above() throws -> DisplayGeometry {
        try DisplayGeometry(
            id: 4, frame: Rect2D(x: -380, y: 1169, width: 2560, height: 1440),
            visibleFrame: Rect2D(x: -380, y: 1169, width: 2560, height: 1415), safeAreaTop: 0,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil, isBuiltIn: false)
    }

    /// The recorded display first (the menu-bar display), the 1080p display to its left, one above.
    public static func sideBySide() throws -> [DisplayGeometry] {
        [try mbp14MoreSpace(), try noNotch1080(), try above()]
    }

    public static func all() throws -> [DisplayGeometry] {
        [try mbp14MoreSpace(), try noNotch1080(), try safeAreaWithoutAux(), try above()]
    }

    /// `display` moved by (dx, dy) with every rectangle, so shell tests keep their panels off every real screen.
    public static func moved(_ display: DisplayGeometry, dx: Double, dy: Double, id: UInt32? = nil) throws
        -> DisplayGeometry
    {
        func move(_ r: Rect2D) -> Rect2D { Rect2D(x: r.x + dx, y: r.y + dy, width: r.width, height: r.height) }
        return try DisplayGeometry(
            id: id ?? display.id, frame: move(display.frame), visibleFrame: move(display.visibleFrame),
            safeAreaTop: display.safeAreaTop, auxiliaryTopLeft: display.auxiliaryTopLeft.map(move),
            auxiliaryTopRight: display.auxiliaryTopRight.map(move), isBuiltIn: display.isBuiltIn)
    }
}

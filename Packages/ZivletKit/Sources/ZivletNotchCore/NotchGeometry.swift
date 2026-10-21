import ZivletCore

/// The camera housing from public screen values (design/19 §3.2, spike S1). No size is hard-coded: the housing is
/// the gap between the two auxiliary top areas, as tall as the safe-area inset, flush with the display's top edge.
public enum NotchGeometry {
    /// Nil unless the display reports a safe area, both auxiliary areas, and a right area that starts after the left
    /// one ends. A display with a safe area but no auxiliary areas gets the pill.
    public static func housing(of display: DisplayGeometry) -> Rect2D? {
        guard display.safeAreaTop > 0, let left = display.auxiliaryTopLeft, let right = display.auxiliaryTopRight,
            right.minX > left.maxX
        else { return nil }
        let height = display.safeAreaTop
        return Rect2D(x: left.maxX, y: display.frame.maxY - height, width: right.minX - left.maxX, height: height)
    }

    public static func hasNotch(_ display: DisplayGeometry) -> Bool { housing(of: display) != nil }

    /// The latch behind "this Mac has a built-in notch" (D-M5a-11): true once a built-in display with a housing has
    /// been seen, and never false again, so closing the lid does not change "Automatic".
    public static func builtInNotchSeen(before: Bool, displays: [DisplayGeometry]) -> Bool {
        before || displays.contains { $0.isBuiltIn && hasNotch($0) }
    }
}

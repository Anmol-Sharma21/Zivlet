import ZivletCore

extension IslandLayout.Metrics {
    /// The tray zone's height when a display reports no menu-bar band (menu bar hidden, or a full-screen Space).
    public static let minimumTrayBand = 24.0
}

extension IslandLayout {
    /// Where a resting file drag opens the tray (D-M5b-9), in global points with y up. On a display with a housing:
    /// the housing widened by `margin` on each side, as tall as the housing, at the top edge. Without one: the
    /// menu-bar band above the pill, the pill's collapsed width plus `margin` on each side, centred. The caller passes
    /// `NotchProximity.Config.margin`, so the constant lives in one place. A negative margin counts as none.
    public static func trayZone(on display: DisplayGeometry, margin: Double) -> Rect2D {
        let margin = max(margin, 0)
        if let housing = NotchGeometry.housing(of: display) {
            return Rect2D(
                x: housing.minX - margin, y: housing.minY, width: housing.width + 2 * margin, height: housing.height)
        }
        let band = max(display.frame.maxY - display.visibleFrame.maxY, Metrics.minimumTrayBand)
        let width = Metrics.pillCollapsed.width + 2 * margin
        return Rect2D(x: display.frame.midX - width / 2, y: display.frame.maxY - band, width: width, height: band)
    }
}

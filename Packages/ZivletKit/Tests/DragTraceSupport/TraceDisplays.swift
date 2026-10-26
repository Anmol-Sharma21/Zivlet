import NotchTestSupport
import ZivletCore
import ZivletNotchCore
import ZivletTrigger

/// The displays the synthetic replays run on, taken from the notch display fixtures so there is one set of numbers:
/// the recorded 14-inch display (a housing) and the constructed 1080p display (the pill).
extension TraceDisplay {
    public static func mbp14() throws -> TraceDisplay { TraceDisplay(try DisplayFixtures.mbp14MoreSpace()) }
    public static func pill1080() throws -> TraceDisplay { TraceDisplay(try DisplayFixtures.noNotch1080()) }

    public init(_ display: DisplayGeometry) {
        self.init(
            id: display.id, frame: display.frame, visibleFrame: display.visibleFrame, safeAreaTop: display.safeAreaTop,
            auxiliaryTopLeft: display.auxiliaryTopLeft, auxiliaryTopRight: display.auxiliaryTopRight)
    }

    /// The display as the island reads it, through the island's own checks.
    public func geometry() throws -> DisplayGeometry {
        try DisplayGeometry(
            id: id, frame: frame, visibleFrame: visibleFrame, safeAreaTop: safeAreaTop,
            auxiliaryTopLeft: auxiliaryTopLeft, auxiliaryTopRight: auxiliaryTopRight, isBuiltIn: false)
    }

    /// The zone the island would use (`IslandLayout.trayZone`): where notch-bound drags aim and what the rule watches.
    public func target() throws -> Rect2D { IslandLayout.trayZone(on: try geometry(), margin: 0) }
}

/// The island's tray zones for a trace's display, as the app builds them (D-M5b-9).
public enum TraceZones {
    public static func zones(for display: TraceDisplay, margin: Double) -> [NotchProximity.Zone] {
        guard let geometry = try? display.geometry() else { return [] }
        return [NotchProximity.Zone(display: display.id, rect: IslandLayout.trayZone(on: geometry, margin: margin))]
    }

    /// The zones for `config`'s margin, for `TraceEvaluator.score`.
    public static func provider(_ config: NotchProximity.Config) -> (TraceDisplay) -> [NotchProximity.Zone] {
        { zones(for: $0, margin: config.margin) }
    }
}

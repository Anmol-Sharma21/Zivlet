import Foundation
import ZivletCore

/// Wheel constants in points (03a §2.2) and pure angle maths (03a §2.3).
public struct WheelGeometry: Sendable, Equatable {
    public static let standard = WheelGeometry()

    public let hubRadius = 42.24
    public let petalInner = 48.64
    public let petalOuter = 119.52
    public let ringOuter = 125.92
    public let gap = 4.0
    public let outerCornerInset = 20.16
    public let entryRadius = 50.4
    public let outerSlack = 150.0
    public let hysteresis = 3.0 * Double.pi / 180
    public let panelSide = 372.0
    public let maxSlots = WheelLimits.maxSlots

    /// 40 + (119.52 − 40) × 0.56 = 84.5312.
    public var labelRadius: Double { 40 + (petalOuter - 40) * 0.56 }

    public func span(count: Int) -> Double { 2 * .pi / Double(max(count, 1)) }

    /// Slot 0 at 12 o'clock, clockwise; three slots start at 9 o'clock.
    public func baseAngle(count: Int) -> Double { count == 3 ? .pi : .pi / 2 }

    /// Centre angle of `slot` in AppKit radians (counter-clockwise from +x).
    public func centreAngle(slot: Int, count: Int) -> Double {
        baseAngle(count: count) - Double(slot) * span(count: count)
    }

    public func labelPoint(slot: Int, count: Int) -> Point2D {
        let a = centreAngle(slot: slot, count: count)
        return Point2D(x: labelRadius * cos(a), y: labelRadius * sin(a))
    }

    /// Half-angle removed at radius r so the gap stays 4 pt wide: asin(min(2/r, 0.95)).
    public func edgeInset(atRadius r: Double) -> Double {
        asin(min((gap / 2) / r, 0.95))
    }

    /// Angular corner insets for the petal outline (outer, inner).
    public func cornerInsets(count: Int) -> (outer: Double, inner: Double) {
        let s = span(count: count)
        return (min(0.24 * s, 0.15), min(0.18 * s, 0.18))
    }
}

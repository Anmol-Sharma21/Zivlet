import Foundation
import ZivletCore

public enum HitResult: Sendable, Equatable {
    case hub  // drop = cancel (snap back)
    case slot(Int)
    case outside
}

/// Pure hit-testing (03a §2.4). Points are relative to the wheel centre, y up.
public struct WheelHitTester: Sendable {
    public let geometry: WheelGeometry
    public init(geometry: WheelGeometry = .standard) { self.geometry = geometry }

    /// Forgiving mode: gaps belong to the nearer slot, slack to r 150, 3° hysteresis against `current`.
    public func hitTest(_ p: Point2D, count: Int, current: Int? = nil) -> HitResult {
        let r = (p.x * p.x + p.y * p.y).squareRoot()
        if r < geometry.hubRadius { return .hub }
        if r > geometry.outerSlack || count < 1 { return .outside }
        let a = clockwiseAngle(p, count: count)
        let span = geometry.span(count: count)
        let slot = Int((a / span).rounded(.toNearestOrAwayFromZero)) % count
        if let current, current != slot, current < count,
            angularDistance(a, Double(current) * span) < span / 2 + geometry.hysteresis
        {
            return .slot(current)
        }
        return .slot(slot)
    }

    /// Exact petal containment (03a §2.4): inside the petal annulus and outside both 4 pt gap bands.
    public func petalContains(_ p: Point2D, slot: Int, count: Int) -> Bool {
        let r = (p.x * p.x + p.y * p.y).squareRoot()
        guard r >= geometry.petalInner, r <= geometry.petalOuter, count >= 1 else { return false }
        if count == 1 { return true }
        let offset = angularDistance(clockwiseAngle(p, count: count), Double(slot) * geometry.span(count: count))
        return offset <= geometry.span(count: count) / 2 - geometry.edgeInset(atRadius: r)
    }

    /// Clockwise angle from slot 0's centre, in [0, 2π).
    func clockwiseAngle(_ p: Point2D, count: Int) -> Double {
        let raw = (geometry.baseAngle(count: count) - atan2(p.y, p.x)).truncatingRemainder(dividingBy: 2 * .pi)
        return raw < 0 ? raw + 2 * .pi : raw
    }

    func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
        return min(d, 2 * .pi - d)
    }
}

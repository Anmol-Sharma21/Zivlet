import SwiftUI
import ZivletWheelCore

/// Maps WheelCore's polar maths (AppKit, y up) into the 372 pt SwiftUI frame (y down).
nonisolated enum WheelLayout {
    static let geometry = WheelGeometry.standard
    static let centre = CGPoint(x: geometry.panelSide / 2, y: geometry.panelSide / 2)

    static func point(radius: Double, angle: Double, in rect: CGRect? = nil) -> CGPoint {
        let c = rect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? centre
        return CGPoint(x: c.x + radius * cos(angle), y: c.y - radius * sin(angle))
    }

    static func labelPoint(slot: Int, count: Int) -> CGPoint {
        point(radius: geometry.labelRadius, angle: geometry.centreAngle(slot: slot, count: count))
    }
}

/// Annulus; also the single-slot petal and the backdrop disk.
nonisolated struct RingShape: Shape {
    let inner: Double
    let outer: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addRelativeArc(center: c, radius: outer, startAngle: .zero, delta: .radians(2 * .pi))
        path.closeSubpath()
        path.addRelativeArc(center: c, radius: inner, startAngle: .zero, delta: .radians(-2 * .pi))
        path.closeSubpath()
        return path
    }
}

/// One petal (03a §2.2): annular sector from r 48.64 to 119.52 with a constant 4 pt gap to its neighbours and
/// rounded corners. Outer corners start 20.16 pt inside the rim with angular inset min(0.24·span, 0.15); inner
/// corners rise 8 pt [new] with inset min(0.18·span, 0.18). The curve itself is Zivlet's own construction.
/// `grow` (1.05 when highlighted) scales the outline about the wheel centre, so the petal grows outward and the
/// glass stays on its petal. It is the only `var`: SwiftUI animates it through `animatableData`.
nonisolated struct PetalShape: Shape {
    static let innerCornerRise = 8.0
    let slot: Int
    let count: Int
    var grow = 1.0
    let geometry = WheelGeometry.standard

    init(slot: Int, count: Int, grow: Double = 1) {
        self.slot = slot
        self.count = count
        self.grow = grow
    }

    var animatableData: Double {
        get { grow }
        set { grow = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outline = outline(in: rect)
        guard grow != 1 else { return outline }
        let scale = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: grow, y: grow)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return outline.applying(scale)
    }

    private func outline(in rect: CGRect) -> Path {
        let g = geometry
        guard count > 1 else { return RingShape(inner: g.petalInner, outer: g.petalOuter).path(in: rect) }
        let span = g.span(count: count)
        let start = g.centreAngle(slot: slot, count: count) + span / 2  // counter-clockwise edge
        let end = start - span  // clockwise edge
        let (outerInset, innerInset) = g.cornerInsets(count: count)
        let rimCorner = g.petalOuter - g.outerCornerInset
        let hubCorner = g.petalInner + Self.innerCornerRise
        func p(_ r: Double, _ a: Double) -> CGPoint { WheelLayout.point(radius: r, angle: a, in: rect) }
        func e(_ r: Double) -> Double { g.edgeInset(atRadius: r) }
        let outerFrom = start - e(g.petalOuter) - outerInset
        let outerTo = end + e(g.petalOuter) + outerInset
        let innerFrom = end + e(g.petalInner) + innerInset
        let innerTo = start - e(g.petalInner) - innerInset
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: p(hubCorner, start - e(hubCorner)))
        path.addLine(to: p(rimCorner, start - e(rimCorner)))
        path.addQuadCurve(to: p(g.petalOuter, outerFrom), control: p(g.petalOuter, start - e(g.petalOuter)))
        path.addRelativeArc(
            center: c, radius: g.petalOuter, startAngle: .radians(-outerFrom), delta: .radians(outerFrom - outerTo))
        path.addQuadCurve(to: p(rimCorner, end + e(rimCorner)), control: p(g.petalOuter, end + e(g.petalOuter)))
        path.addLine(to: p(hubCorner, end + e(hubCorner)))
        path.addQuadCurve(to: p(g.petalInner, innerFrom), control: p(g.petalInner, end + e(g.petalInner)))
        path.addRelativeArc(
            center: c, radius: g.petalInner, startAngle: .radians(-innerFrom), delta: .radians(innerFrom - innerTo))
        path.addQuadCurve(to: p(hubCorner, start - e(hubCorner)), control: p(g.petalInner, start - e(g.petalInner)))
        path.closeSubpath()
        return path
    }
}

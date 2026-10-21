import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletWheelCore

@Suite("Hit testing (P0-25, 03a §2.4)")
struct WheelHitTesterTests {
    let tester = WheelHitTester()
    let g = WheelGeometry.standard

    func polar(_ r: Double, _ angle: Double) -> Point2D { Point2D(x: r * cos(angle), y: r * sin(angle)) }

    @Test func hubAndOutside() {
        #expect(tester.hitTest(Point2D(x: 10, y: 10), count: 6) == .hub)
        #expect(tester.hitTest(polar(42.23, 1), count: 6) == .hub)
        #expect(tester.hitTest(polar(150.01, 1), count: 6) == .outside)
        #expect(tester.hitTest(polar(140, .pi / 2), count: 6) == .slot(0), "slack beyond the rim still hits")
        #expect(tester.hitTest(polar(80, 0), count: 0) == .outside)
    }

    @Test(arguments: 1...12)
    func everySlotCentreHitsItsSlot(count: Int) {
        for slot in 0..<count {
            let p = polar(g.labelRadius, g.centreAngle(slot: slot, count: count))
            #expect(tester.hitTest(p, count: count) == .slot(slot))
        }
    }

    @Test func threeSlotsStartAtNineOClock() {
        #expect(tester.hitTest(Point2D(x: -80, y: 0), count: 3) == .slot(0))
        #expect(tester.hitTest(Point2D(x: 80, y: 0), count: 4) == .slot(1))
    }

    @Test func gapsBelongToTheNearerSlot() {
        let boundary = g.centreAngle(slot: 0, count: 6) - g.span(count: 6) / 2
        #expect(tester.hitTest(polar(80, boundary + 0.01), count: 6) == .slot(0))
        #expect(tester.hitTest(polar(80, boundary - 0.01), count: 6) == .slot(1))
    }

    @Test func hysteresisKeepsCurrentSlotWithinThreeDegrees() {
        let boundary = g.centreAngle(slot: 0, count: 6) - g.span(count: 6) / 2
        let justPast = polar(80, boundary - 2 * .pi / 180)
        #expect(tester.hitTest(justPast, count: 6, current: 0) == .slot(0))
        #expect(tester.hitTest(justPast, count: 6, current: nil) == .slot(1))
        let wellPast = polar(80, boundary - 4 * .pi / 180)
        #expect(tester.hitTest(wellPast, count: 6, current: 0) == .slot(1))
    }

    @Test func petalContainmentExcludesGapsHubAndRim() {
        let boundary = g.centreAngle(slot: 0, count: 6) - g.span(count: 6) / 2
        #expect(tester.petalContains(polar(80, .pi / 2), slot: 0, count: 6))
        #expect(!tester.petalContains(polar(80, boundary), slot: 0, count: 6))
        #expect(!tester.petalContains(polar(80, boundary), slot: 1, count: 6))
        #expect(!tester.petalContains(polar(45, .pi / 2), slot: 0, count: 6))
        #expect(!tester.petalContains(polar(122, .pi / 2), slot: 0, count: 6))
        #expect(tester.petalContains(polar(100, 4), slot: 0, count: 1), "one slot is a full ring")
    }

    /// Exact containment never disagrees with the forgiving hit test, and petals never overlap.
    @Test func containmentAgreesWithHitTestOnTenThousandPoints() {
        var rng = SplitMix64(seed: 2026)
        for _ in 0..<10_000 {
            let count = Int.random(in: 1...12, using: &rng)
            let p = polar(Double.random(in: 0...160, using: &rng), Double.random(in: 0..<(2 * .pi), using: &rng))
            let owners = (0..<count).filter { tester.petalContains(p, slot: $0, count: count) }
            #expect(owners.count <= 1)
            if let owner = owners.first { #expect(tester.hitTest(p, count: count) == .slot(owner)) }
        }
    }
}

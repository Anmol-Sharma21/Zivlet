import Foundation
import Testing
import ZivletCore

@testable import ZivletWheelCore

@Suite("Wheel geometry (P0-24, 03a §2.2–2.3)")
struct WheelGeometryTests {
    let g = WheelGeometry.standard

    @Test func constantsMatchDesign() {
        #expect(g.hubRadius == 42.24 && g.petalInner == 48.64 && g.petalOuter == 119.52 && g.ringOuter == 125.92)
        #expect(g.gap == 4 && g.panelSide == 372 && g.maxSlots == 12 && g.outerSlack == 150)
        #expect(abs(g.labelRadius - 84.5312) < 1e-9)
    }

    @Test(arguments: 1...12)
    func slotZeroIsAtTwelveOClockExceptThreeSlots(count: Int) {
        let expected = count == 3 ? Double.pi : .pi / 2
        #expect(abs(g.centreAngle(slot: 0, count: count) - expected) < 1e-12)
    }

    @Test func slotsRunClockwise() {
        #expect(abs(g.centreAngle(slot: 1, count: 4) - 0) < 1e-12)  // 3 o'clock
        #expect(abs(g.centreAngle(slot: 2, count: 4) - -Double.pi / 2) < 1e-12)  // 6 o'clock
        #expect(abs(g.centreAngle(slot: 1, count: 3) - Double.pi / 3) < 1e-12)  // 9 → upper right
        let label = g.labelPoint(slot: 0, count: 6)
        #expect(abs(label.x) < 1e-9 && abs(label.y - g.labelRadius) < 1e-9)
    }

    /// Perpendicular distance from a petal edge to the slot boundary ray is r·sin(inset) = gap/2.
    @Test(arguments: [48.64, 84.5312, 119.52])
    func gapIsFourPointsAtEveryRadius(r: Double) {
        let halfGap = r * sin(g.edgeInset(atRadius: r))
        #expect(abs(2 * halfGap - 4) < 0.01)
    }

    @Test func cornerInsetsAreCapped() {
        let six = g.cornerInsets(count: 6)
        #expect(abs(six.outer - 0.15) < 1e-12 && abs(six.inner - 0.18) < 1e-12)
        let twelve = g.cornerInsets(count: 12)
        #expect(abs(twelve.outer - 0.24 * (2 * .pi / 12)) < 1e-12)
    }
}

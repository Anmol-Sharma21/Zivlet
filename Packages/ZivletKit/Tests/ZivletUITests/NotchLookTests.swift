import CoreGraphics
import Testing
import ZivletNotch

@testable import ZivletUI

@Suite("Island tokens (19b §3)")
struct NotchLookTests {
    @Test func spacingIsOnTheFourPointGrid() {
        for value in NotchLook.Spacing.all { #expect(value.truncatingRemainder(dividingBy: 4) == 0) }
    }

    @Test func innerRadiiAreConcentric() {
        #expect(IslandLook.Radius.inner == IslandLook.Radius.card - NotchLook.Spacing.l)
    }

    /// The luminance the ink's contrast tests assume covers the lightest glass measured over white (19b §4.2 P7).
    @Test func theAssumedGlassIsNoDarkerThanTheMeasuredOne() {
        #expect(IslandLook.worstGlassLuminance >= 0.102)
    }

    @Test func theRingsStepsFollowItsStrokeAtTwiceScale() {
        #expect(VisibleProgress.steps(lengthInPoints: NotchLook.Ring.strokeLength, scale: 2) == 84)
        #expect(NotchHUDBoard.ringSteps == 84 && NotchHUDBoard.barSteps == VisibleProgress.maxSteps)
    }
}

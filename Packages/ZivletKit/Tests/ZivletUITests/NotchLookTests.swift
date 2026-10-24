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

    @Test func theScrimIsTheMeasuredOne() {
        #expect(IslandLook.scrim == 0.5)
        #expect(IslandLook.worstGlassLuminance >= 0.102)
    }

    @Test func theRingsStepsFollowItsStrokeAtTwiceScale() {
        #expect(VisibleProgress.steps(lengthInPoints: NotchLook.Ring.strokeLength, scale: 2) == 84)
        #expect(NotchHUDBoard.ringSteps == 84 && NotchHUDBoard.barSteps == VisibleProgress.maxSteps)
        #expect(NotchLook.Symbol.buttonSide == 28 && NotchLook.Ring.side == 16)
    }

    @Test func theRadiiFollowTheSurface() {
        #expect(IslandLook.Radius.tab == 12 && IslandLook.Radius.toast == 18)
    }
}

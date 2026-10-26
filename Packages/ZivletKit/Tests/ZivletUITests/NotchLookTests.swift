import CoreGraphics
import Testing
import ZivletNotch

@testable import ZivletUI

@Suite("Island tokens in the notch HUD (19b §3)")
struct NotchLookTests {
    @Test func theHUDReadsTheSharedTokens() {
        #expect(NotchLook.Spacing.l == IslandContentLook.Spacing.l && NotchInk.secondaryOpacity == 0.8)
    }

    @Test func theRingsStepsFollowItsStrokeAtTwiceScale() {
        #expect(VisibleProgress.steps(lengthInPoints: NotchLook.Ring.strokeLength, scale: 2) == 84)
        #expect(NotchHUDBoard.ringSteps == 84 && NotchHUDBoard.barSteps == VisibleProgress.maxSteps)
    }
}

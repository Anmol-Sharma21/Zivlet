import CoreGraphics
import Testing

@testable import ZivletNotch

@Suite("Island content tokens (19b §3)")
struct IslandContentLookTests {
    @Test func spacingIsOnTheFourPointGrid() {
        for value in IslandContentLook.Spacing.all { #expect(value.truncatingRemainder(dividingBy: 4) == 0) }
    }

    @Test func innerRadiiAreConcentric() {
        #expect(IslandLook.Radius.inner == IslandLook.Radius.card - IslandContentLook.Spacing.l)
    }

    /// The luminance the ink's contrast tests assume covers the lightest glass measured over white (19b §4.2 P7).
    @Test func theAssumedGlassIsNoDarkerThanTheMeasuredOne() {
        #expect(IslandLook.worstGlassLuminance >= 0.102)
    }
}

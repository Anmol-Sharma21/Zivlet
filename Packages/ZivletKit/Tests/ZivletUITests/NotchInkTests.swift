import Testing

@testable import ZivletUI

@Suite("Island ink (D-N10, NFR-14 ≥ 4.5:1, non-text ≥ 3:1)")
struct NotchInkTests {
    @Test func whiteAndSecondaryTextOnBlackPassWithMargin() {
        #expect(NotchInk.contrast(textOpacity: 1) > 20)
        #expect(NotchInk.contrast(textOpacity: NotchInk.secondaryOpacity) >= 4.5)
    }

    @Test func theRingMeetsNonTextContrast() {  // WCAG 1.4.11, design/19 §5.5
        #expect(NotchInk.contrast(textOpacity: NotchInk.ringTrackOpacity) >= 3)
        #expect(NotchInk.contrast(fill: 1, track: NotchInk.ringTrackOpacity) >= 3)
    }
}

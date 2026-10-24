import Testing
import ZivletNotch

@testable import ZivletUI

@Suite("Island ink on glass, solid and black (19b §3.5, NFR-14 ≥ 4.5:1, non-text ≥ 3:1)")
struct NotchInkTests {
    private let worst = IslandLook.worstGlassLuminance
    private var solid: Double { HUDInk.luminance(IslandLook.solidGrey) }

    @Test func textOnTheWorstGlassPasses() {
        #expect(NotchInk.contrast(textOpacity: 1, over: worst) >= 6)
        #expect(NotchInk.contrast(textOpacity: NotchInk.secondaryOpacity, over: worst) >= 4.5)
    }

    @Test func progressMeetsNonTextContrastOnTheWorstGlass() {  // WCAG 1.4.11
        #expect(NotchInk.contrast(fillOver: worst) >= 3)
        #expect(NotchInk.contrast(fill: 1, track: NotchInk.trackOpacity, over: worst) >= 3)
    }

    @Test func theSolidFallbackPassesWithMargin() {
        #expect(NotchInk.contrast(textOpacity: 1, over: solid) >= 16)
        #expect(NotchInk.contrast(textOpacity: NotchInk.secondaryOpacity, over: solid) >= 11)
        #expect(NotchInk.contrast(fill: 1, track: NotchInk.trackOpacity, over: solid) >= 3)
    }

    @Test func blackStillPasses() {
        #expect(NotchInk.contrast(textOpacity: 1) > 20)
        #expect(NotchInk.contrast(textOpacity: NotchInk.secondaryOpacity) >= 4.5)
        #expect(NotchInk.contrast(fillOver: 0) >= 3)
        #expect(NotchInk.contrast(fill: 1, track: NotchInk.trackOpacity) >= 3)
    }

    @Test func greyAndLuminanceAreInverse() {
        for grey in [0.0, 0.02, 0.11, 0.5, 1] {
            #expect(abs(NotchInk.grey(ofLuminance: HUDInk.luminance(grey)) - grey) < 1e-9)
        }
    }
}

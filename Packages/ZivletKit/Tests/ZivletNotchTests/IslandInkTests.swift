import Testing

@testable import ZivletNotch

@Suite("Island ink on glass, solid and black (19b §3.5, NFR-14 ≥ 4.5:1, non-text ≥ 3:1)")
struct IslandInkTests {
    private let worst = IslandLook.worstGlassLuminance
    private var solid: Double { IslandInk.luminance(IslandLook.solidGrey) }

    @Test func textOnTheWorstGlassPasses() {
        #expect(IslandInk.contrast(textOpacity: 1, over: worst) >= 6)
        #expect(IslandInk.contrast(textOpacity: IslandInk.secondaryOpacity, over: worst) >= 4.5)
    }

    @Test func progressMeetsNonTextContrastOnTheWorstGlass() {  // WCAG 1.4.11
        #expect(IslandInk.contrast(fillOver: worst) >= 3)
        #expect(IslandInk.contrast(fill: 1, track: IslandInk.trackOpacity, over: worst) >= 3)
    }

    @Test func theSolidFallbackPassesWithMargin() {
        #expect(IslandInk.contrast(textOpacity: 1, over: solid) >= 16)
        #expect(IslandInk.contrast(textOpacity: IslandInk.secondaryOpacity, over: solid) >= 11)
        #expect(IslandInk.contrast(fill: 1, track: IslandInk.trackOpacity, over: solid) >= 3)
    }

    @Test func blackStillPasses() {
        #expect(IslandInk.contrast(textOpacity: 1) > 20)
        #expect(IslandInk.contrast(textOpacity: IslandInk.secondaryOpacity) >= 4.5)
        #expect(IslandInk.contrast(fillOver: 0) >= 3)
        #expect(IslandInk.contrast(fill: 1, track: IslandInk.trackOpacity) >= 3)
    }

    @Test func greyAndLuminanceAreInverse() {
        for grey in [0.0, 0.02, 0.11, 0.5, 1] {
            #expect(abs(IslandInk.grey(ofLuminance: IslandInk.luminance(grey)) - grey) < 1e-9)
        }
    }
}

import NotchTestSupport
import Testing
import ZivletCore

@testable import ZivletNotchCore

@Suite("Display geometry in diagnostics (Q15)")
struct DisplayDiagnosticsTests {
    @Test func oneLinePerDisplayWithEveryValueAndTheHousing() throws {
        #expect(
            try DisplayFixtures.mbp14MoreSpace().diagnosticsLine
                == "display 1: frame 0 0 1800 1169 · visible 0 94 1800 1036 · safe top 38 · aux left 0 1131 790 38 · aux right 1010 1131 790 38 · housing 790 1131 220 38 · built in"
        )
    }

    @Test func aDisplayWithoutANotchSaysSo() throws {
        let line = try DisplayFixtures.noNotch1080().diagnosticsLine
        #expect(
            line
                == "display 2: frame -1920 0 1920 1080 · visible -1920 0 1920 1055 · safe top 0 · aux left none · aux right none · housing none"
        )
    }

    @Test func fractionalPointsKeepTheirFraction() throws {
        let display = try DisplayGeometry(
            id: 7, frame: Rect2D(x: 0, y: 0, width: 1512, height: 982.5),
            visibleFrame: Rect2D(x: 0, y: 0, width: 1512, height: 944.25), safeAreaTop: 37.5,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil, isBuiltIn: true)
        #expect(
            display.diagnosticsLine.hasPrefix(
                "display 7: frame 0 0 1512 982.5 · visible 0 0 1512 944.25 · safe top 37.5"))
        #expect(display.diagnosticsLine.hasSuffix("· housing none · built in"))
    }
}

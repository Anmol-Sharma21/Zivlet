import NotchTestSupport
import Testing
import ZivletCore

@testable import ZivletNotchCore

@Suite("Tray zone (D-M5b-9)")
struct TrayZoneTests {
    @Test func theRecordedNotchGivesTheHousingWidenedBy40() throws {
        #expect(
            IslandLayout.trayZone(on: try DisplayFixtures.mbp14MoreSpace(), margin: 40)
                == Rect2D(x: 750, y: 1131, width: 300, height: 38))
    }

    @Test func aDisplayWithoutANotchUsesTheMenuBarAboveThePill() throws {
        #expect(
            IslandLayout.trayZone(on: try DisplayFixtures.noNotch1080(), margin: 40)
                == Rect2D(x: -1100, y: 1055, width: 280, height: 25))
    }

    @Test func aSafeAreaWithoutAuxiliaryAreasUsesThePillRule() throws {
        let display = try DisplayFixtures.safeAreaWithoutAux()
        #expect(
            IslandLayout.trayZone(on: display, margin: 40)
                == Rect2D(x: 756 - 140, y: 943, width: 280, height: 39))
    }

    @Test func noMarginIsTheHousingItself() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(IslandLayout.trayZone(on: display, margin: 0) == NotchGeometry.housing(of: display))
    }

    @Test func aNegativeMarginCountsAsNone() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(IslandLayout.trayZone(on: display, margin: -10) == NotchGeometry.housing(of: display))
    }

    @Test func aDisplayWithoutAMenuBarBandStillGetsAThinZoneAtItsTop() throws {
        let display = try DisplayGeometry(
            id: 9, frame: Rect2D(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: Rect2D(x: 0, y: 0, width: 1000, height: 800), safeAreaTop: 0,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil, isBuiltIn: false)
        #expect(
            IslandLayout.trayZone(on: display, margin: 40)
                == Rect2D(
                    x: 360, y: 800 - IslandLayout.Metrics.minimumTrayBand, width: 280,
                    height: IslandLayout.Metrics.minimumTrayBand))
    }
}

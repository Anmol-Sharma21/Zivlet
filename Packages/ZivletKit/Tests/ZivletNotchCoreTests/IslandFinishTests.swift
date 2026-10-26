import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotchCore

@Suite("Island finish (OWN-UI-1, 19b D-NL1, D-NL3)")
struct IslandFinishTests {
    @Test(arguments: [
        (IslandSurface.collapsed, true, false, false, IslandFinish.black(outline: false)),
        (.toast, true, false, false, .glass(band: 38)),
        (.expanded, true, false, false, .glass(band: 38)),
        (.collapsed, false, false, false, .glass(band: 0)),
        (.toast, false, false, false, .glass(band: 0)),
        (.toast, true, true, false, .solid(band: 38, outline: false)),
        (.expanded, true, false, true, .solid(band: 38, outline: true)),
        (.collapsed, true, true, true, .black(outline: true)),
        (.collapsed, false, true, false, .solid(band: 0, outline: false)),
        (.expanded, false, false, true, .solid(band: 0, outline: true)),
    ])
    func finishFollowsSurfaceDisplayAndSettings(
        surface: IslandSurface, notch: Bool, reduceTransparency: Bool, increaseContrast: Bool, expected: IslandFinish
    ) throws {
        let display = try notch ? DisplayFixtures.mbp14MoreSpace() : DisplayFixtures.noNotch1080()
        let settings = IslandFinish.Settings(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
        #expect(IslandFinish.resolve(surface, on: display, settings: settings) == expected)
    }

    @Test(arguments: [false, true])
    func increaseContrastOutlinesEveryFinish(increaseContrast: Bool) throws {
        let settings = IslandFinish.Settings(reduceTransparency: false, increaseContrast: increaseContrast)
        let notch = try DisplayFixtures.mbp14MoreSpace()
        let pill = try DisplayFixtures.noNotch1080()
        for (surface, display) in [(IslandSurface.collapsed, notch), (.toast, notch), (.expanded, pill)] {
            #expect(IslandFinish.resolve(surface, on: display, settings: settings).outlined == increaseContrast)
        }
    }

    @Test func onlyGlassIsTranslucent() {
        #expect(IslandFinish.glass(band: 38).isGlass)
        #expect(!IslandFinish.black(outline: false).isGlass && !IslandFinish.solid(band: 0, outline: false).isGlass)
    }

    @Test func hiddenKeepsTheLastFinish() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        let previous = IslandFinish.solid(band: 38, outline: true)
        #expect(IslandFinish.resolve(.hidden, on: display, settings: .standard, previous: previous) == previous)
        #expect(IslandFinish.resolve(.hidden, on: display, settings: .standard) == .black(outline: false))
    }

    @Test func theBandIsTheHousingHeight() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        let housing = try #require(NotchGeometry.housing(of: display))
        #expect(IslandFinish.resolve(.toast, on: display, settings: .standard).band == housing.height)
        #expect(IslandFinish.black(outline: false).band == 0)
    }
}

@Suite("Floating finish: surfaces that never meet the housing (19c D-BL1)")
struct FloatingFinishTests {
    @Test(arguments: [
        (false, false, IslandFinish.glass(band: 0)), (true, false, .solid(band: 0, outline: false)),
        (false, true, .solid(band: 0, outline: true)),
    ])
    func floatingSurfacesAreGlassOrSolid(reduceTransparency: Bool, increaseContrast: Bool, expected: IslandFinish) {
        let settings = IslandFinish.Settings(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
        #expect(IslandFinish.floating(settings: settings) == expected)
    }
}

import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotchCore

extension IslandRequest {
    /// The tray's drop target: hover does not change it.
    static func trayDrop(display: UInt32 = 1) -> IslandRequest {
        IslandRequest(client: .tray, display: display, resting: .dropTarget, hoverSurface: .dropTarget)
    }
}

@Suite("Tray surfaces: drop target and sensor (D-M5b-6, D-M5b-17)")
struct IslandTraySurfaceTests {
    let t0 = Duration.seconds(100)

    @Test func theDropTargetTakesTheToastsFrame() throws {
        for display in try DisplayFixtures.all() {
            #expect(IslandLayout.frame(.dropTarget, on: display) == IslandLayout.frame(.toast, on: display))
        }
    }

    @Test func theSensorIsTheHousingOnANotchDisplay() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(IslandLayout.frame(.sensor, on: display) == NotchGeometry.housing(of: display))
        #expect(IslandLayout.frame(.sensor, on: display) == Rect2D(x: 790, y: 1131, width: 220, height: 38))
    }

    @Test func thereIsNoSensorOnAPillDisplay() throws {
        for display in [try DisplayFixtures.noNotch1080(), try DisplayFixtures.safeAreaWithoutAux()] {
            #expect(IslandLayout.frame(.sensor, on: display) == Rect2D(x: 0, y: 0, width: 0, height: 0))
        }
    }

    @Test func theDropTargetIsFloatingAndTheSensorBlack() throws {
        let notch = try DisplayFixtures.mbp14MoreSpace()
        let settings = IslandFinish.Settings.standard
        #expect(IslandFinish.resolve(.dropTarget, on: notch, settings: settings) == .glass(band: 38))
        #expect(
            IslandFinish.resolve(
                .sensor, on: notch,
                settings: IslandFinish.Settings(
                    reduceTransparency: false, increaseContrast: true)) == .black(outline: false))
    }

    @Test func aDropTargetShowsAtOnceAndHoverDoesNotChangeIt() {
        let (m, effects) = IslandMachine().handling(.request(.trayDrop(), now: t0))
        #expect(m.surface == .dropTarget && effects == [.show(.dropTarget, display: 1, contentHeight: 0)])
        let hovered = m.after([.pointerEntered(now: t0), .tick(now: t0 + .seconds(1))])
        #expect(hovered.surface == .dropTarget)
        #expect(m.after([.accessibilityFocused(now: t0)]).surface == .dropTarget)
    }

    @Test func aDropTargetReplacesAnOpenCardAtOnce() {
        let open = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)),
        ])
        #expect(open.surface == .expanded)
        let (m, _) = open.handling(.request(.trayDrop(), now: t0 + .seconds(1)))
        #expect(m.surface == .dropTarget && m.hover == .outside)
    }

    @Test func hoverOnTheSensorOpensAfterTheIntentAndGraceReturnsToIt() {
        let sensor = IslandMachine().handling(.request(.tray(.sensor), now: t0)).0
        #expect(sensor.surface == .sensor)
        let entered = sensor.handling(.pointerEntered(now: t0)).0
        #expect(entered.handling(.tick(now: t0 + .milliseconds(149))).0.surface == .sensor)
        let open = entered.handling(.tick(now: t0 + .milliseconds(150))).0
        #expect(open.surface == .expanded)
        let leaving = open.handling(.pointerExited(now: t0 + .seconds(1))).0
        #expect(leaving.handling(.tick(now: t0 + .seconds(1) + .milliseconds(299))).0.surface == .expanded)
        #expect(leaving.handling(.tick(now: t0 + .seconds(1) + .milliseconds(300))).0.surface == .sensor)
    }

    @Test func leavingTheDropTargetGoesBackToTheSensor() {
        let drop = IslandMachine().handling(.request(.trayDrop(), now: t0)).0
        let (m, effects) = drop.handling(.request(.tray(.sensor), now: t0 + .seconds(1)))
        #expect(m.surface == .sensor && effects == [.show(.sensor, display: 1, contentHeight: 0)])
    }
}

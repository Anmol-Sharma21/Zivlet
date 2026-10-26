import AppKit
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotchCore

@testable import ZivletNotch

@Suite("Tray surfaces in the host (D-M5b-6, D-M5b-17)")
@MainActor
struct IslandTraySurfaceHostTests {
    private func tray(_ resting: IslandSurface, display: UInt32) -> IslandRequest {
        IslandRequest(client: .tray, display: display, resting: resting, hoverSurface: .expanded)
    }

    @Test func theSensorSitsOnTheHousingWithoutAFlare() throws {
        let provider = try FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: provider, clock: ManualClock(), animation: .instant)
        hosts.register(FakeClient(), as: .tray)
        hosts.request(tray(.sensor, display: 1), from: .tray)
        let host = try #require(hosts.host(on: 1))
        let housing = try #require(NotchGeometry.housing(of: provider.displays[0]))
        #expect(host.isVisible && host.frame == housing.cgRect)
        #expect(host.chrome.flare == 0 && host.chrome.finish == .black(outline: false))
        hosts.close()
    }

    @Test func aSensorOnAPillDisplayIsOrderedOut() async throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchAndExternal(), clock: ManualClock(), animation: .instant)
        var reported: [(IslandSurface, CGRect)] = []
        hosts.onSurface = { _, surface, frame in reported.append((surface, frame)) }
        hosts.register(FakeClient(), as: .tray)
        hosts.request(tray(.sensor, display: 2), from: .tray)
        await hosts.host(on: 2)?.animationsSettled()
        #expect(hosts.surface(on: 2) == .sensor && hosts.host(on: 2)?.isVisible == false)
        #expect(reported.last?.0 == .sensor && reported.last?.1 == .zero)
        hosts.close()
    }

    @Test func theDropTargetTakesTheToastsFrame() throws {
        let provider = try FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: provider, clock: ManualClock(), animation: .instant)
        hosts.register(FakeClient(), as: .tray)
        hosts.request(
            IslandRequest(client: .tray, display: 1, resting: .dropTarget, hoverSurface: .dropTarget), from: .tray)
        #expect(hosts.host(on: 1)?.frame == IslandLayout.frame(.toast, on: provider.displays[0]).cgRect)
        hosts.close()
    }

    @Test func theHUDsTabStaysWhileTheTrayRestsOnItsSensor() throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchOnly(), clock: ManualClock(), animation: .instant)
        hosts.register(FakeClient(name: "hud"), as: .hud)
        hosts.register(FakeClient(name: "tray"), as: .tray)
        hosts.request(IslandRequest(client: .hud, display: 1, resting: .collapsed, hoverSurface: .expanded), from: .hud)
        hosts.request(tray(.sensor, display: 1), from: .tray)
        #expect(hosts.activeClient(on: 1) == .hud && hosts.surface(on: 1) == .collapsed)
        hosts.request(nil, from: .hud)
        #expect(hosts.activeClient(on: 1) == .tray && hosts.surface(on: 1) == .sensor)
        hosts.close()
    }
}

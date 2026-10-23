import AppKit
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore

@testable import ZivletUI

@Suite("Notch HUD appears quickly (P1-40 budget: ≤ 50 ms)")
@MainActor
struct NotchHUDTimingTests {
    @Test func aDropShowsTheIslandWithin50ms() throws {
        let displays = try FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: displays)  // as AppDelegate builds it: hosts pre-warmed (D-N8, D-N9)
        defer { hosts.close() }
        let hud = NotchHUD(hosts: hosts, provider: displays)
        let snapshot = try HUDFx.snapshot(submitted: 1)
        let start = ContinuousClock.now  // the clock starts before prepare and show
        hud.prepare(near: CGPoint(x: -4500, y: -4500))
        hud.show(snapshot)
        let host = try #require(hosts.host(on: 1))
        #expect(host.isVisible)  // a panel on screen, not only machine state
        #expect(host.frame == IslandLayout.frame(.collapsed, on: displays.displays[0]).cgRect)
        #expect(ContinuousClock.now - start < .milliseconds(50))
    }
}

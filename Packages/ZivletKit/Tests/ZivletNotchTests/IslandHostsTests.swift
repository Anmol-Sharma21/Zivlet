import AppKit
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotchCore

@testable import ZivletNotch

@Suite("Island hosts (D-N8, design/19 §5.2)")
@MainActor
struct IslandHostsTests {
    @Test func aPrewarmedHostExistsForEveryDisplayAtLaunch() throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchAndExternal(), clock: ManualClock(), animation: .instant)
        #expect(hosts.displayIDs == [1, 2])
        #expect(hosts.host(on: 1)?.isPrewarmed == true && hosts.host(on: 2)?.isPrewarmed == true)
        #expect(hosts.visibleDisplays.isEmpty)
        hosts.close()
    }

    @Test func aRequestShowsItsRestingSurfaceAndAWithdrawalHidesIt() async throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchAndExternal(), clock: ManualClock(), animation: .instant)
        let client = FakeClient()
        hosts.register(client, as: .hud)
        hosts.request(IslandRequest(client: .hud, display: 2, resting: .collapsed, hoverSurface: .expanded), from: .hud)
        #expect(hosts.visibleDisplays == [2] && hosts.surface(on: 2) == .collapsed)
        hosts.request(nil, from: .hud)
        await hosts.host(on: 2)?.animationsSettled()
        #expect(hosts.visibleDisplays.isEmpty && hosts.surface(on: 2) == .hidden)
        hosts.close()
    }

    @Test func aHigherClientWinsAndHandsTheIslandBack() throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchOnly(), clock: ManualClock(), animation: .instant)
        let hud = FakeClient(name: "hud")
        let tray = FakeClient(name: "tray")
        hosts.register(hud, as: .hud)
        hosts.register(tray, as: .tray)
        hosts.request(IslandRequest(client: .hud, display: 1, resting: .collapsed, hoverSurface: .expanded), from: .hud)
        hosts.request(IslandRequest(client: .tray, display: 1, resting: .toast, hoverSurface: .expanded), from: .tray)
        #expect(hosts.surface(on: 1) == .toast && hosts.activeClient(on: 1) == .tray)
        hosts.request(nil, from: .tray)
        #expect(hosts.surface(on: 1) == .collapsed && hosts.activeClient(on: 1) == .hud)
        hosts.close()
    }

    @Test func theMenuCommandExpandsTheIslandWithItems() throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchAndExternal(), clock: ManualClock(), animation: .instant)
        hosts.register(FakeClient(), as: .hud)
        #expect(!hosts.hasItems)
        hosts.request(IslandRequest(client: .hud, display: 2, resting: .collapsed, hoverSurface: .expanded), from: .hud)
        #expect(hosts.hasItems)
        hosts.expandRequested()
        #expect(hosts.surface(on: 2) == .expanded)
        hosts.close()
    }

    @Test func theWheelSendsAHoverExpansionBackToRest() async throws {
        let clock = ManualClock()
        let hosts = IslandHosts(provider: try FakeDisplayProvider.notchOnly(), clock: clock, animation: .instant)
        hosts.register(FakeClient(), as: .hud)
        hosts.request(IslandRequest(client: .hud, display: 1, resting: .collapsed, hoverSurface: .expanded), from: .hud)
        hosts.host(on: 1)?.trackingEntered()
        await clock.advance(by: .milliseconds(200))
        #expect(hosts.surface(on: 1) == .expanded)
        hosts.wheelShown()
        #expect(hosts.surface(on: 1) == .collapsed)
        hosts.wheelHidden()
        hosts.close()
    }

    @Test func reduceMotionReachesEveryHost() throws {
        let hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchAndExternal(), clock: ManualClock(), animation: .instant)
        hosts.reduceMotionChanged(true)
        #expect(hosts.host(on: 1)?.curves == IslandMotion(reduceMotion: true))
        #expect(hosts.host(on: 2)?.curves == IslandMotion(reduceMotion: true))
        hosts.close()
    }

    @Test func removingADisplayDestroysItsHostAndTellsClientsTheReplacement() async throws {
        let provider = try FakeDisplayProvider.notchAndExternal()
        let hosts = IslandHosts(provider: provider, clock: ManualClock(), animation: .instant)
        let client = FakeClient()
        hosts.register(client, as: .hud)
        hosts.request(IslandRequest(client: .hud, display: 2, resting: .collapsed, hoverSurface: .expanded), from: .hud)
        provider.set([try OffscreenDisplays.notch()])
        #expect(await eventually { hosts.displayIDs == [1] })
        #expect(hosts.host(on: 2) == nil && hosts.visibleDisplays.isEmpty)
        #expect(client.displayChanges.last?.ids == [1] && client.displayChanges.last?.replacing == [2: 1])
        hosts.close()
    }

    @Test func aNewDisplayGetsAPrewarmedHostAndAMovedOneIsReLaidOut() async throws {
        let provider = try FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: provider, clock: ManualClock(), animation: .instant)
        hosts.register(FakeClient(), as: .hud)
        hosts.request(IslandRequest(client: .hud, display: 1, resting: .collapsed, hoverSurface: .expanded), from: .hud)
        let moved = try DisplayFixtures.moved(try OffscreenDisplays.notch(), dx: -200, dy: 0)
        provider.set([moved, try OffscreenDisplays.plain()])
        #expect(await eventually { hosts.displayIDs == [1, 2] })
        #expect(hosts.host(on: 2)?.isPrewarmed == true)
        #expect(hosts.host(on: 1)?.frame == IslandLayout.frame(.collapsed, on: moved).cgRect)
        hosts.close()
    }

    @Test func twoSubscribersBothSeeEachChange() async throws {
        let provider = try FakeDisplayProvider.notchOnly()
        let first = provider.changes
        let second = provider.changes
        provider.set([try OffscreenDisplays.plain()])
        var a = first.makeAsyncIterator()
        var b = second.makeAsyncIterator()
        #expect(await a.next()?.map(\.id) == [2])
        #expect(await b.next()?.map(\.id) == [2])
    }
}

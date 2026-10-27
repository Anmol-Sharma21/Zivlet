import AppKit
import NotchTestSupport
import TestSupport
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore

@testable import ZivletUI

/// What makes P1-40's budget (a drop shows its HUD in ≤ 50 ms) reachable, checked without a quiet scheduler
/// (D-M7-4): the drop path uses the pre-warmed host and builds no panel (D-N8, D-N9), the collapsed island is on
/// screen, the main thread spends under 50 ms of CPU on it (waiting for a busy CPU is not CPU time), and the
/// `drop→island` signpost interval is begun and ended once. The 50 ms of wall time is judged by
/// ZivletTimingTests.NotchHUDTiming below the load limit (`make timing`).
@Suite("Notch HUD drop path (P1-40 budget's structure)")
@MainActor
struct NotchHUDDropPathTests {
    @Test func aDropUsesThePrewarmedHostAndLittleMainThreadTime() throws {
        let displays = try FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: displays)  // as AppDelegate builds it: hosts pre-warmed (D-N8, D-N9)
        defer { hosts.close() }
        let signposts = RecordingSignposts()
        let hud = NotchHUD(hosts: hosts, provider: displays, signposts: signposts)
        let snapshot = try HUDFx.snapshot(submitted: 1)
        let built = hosts.panelsBuilt
        let cpu = ThreadCPUTime.measure {
            hud.prepare(near: CGPoint(x: -4500, y: -4500))
            hud.show(snapshot)
        }
        let host = try #require(hosts.host(on: 1))
        #expect(built == 1)
        #expect(hosts.panelsBuilt == built)  // no panel built on the drop path
        #expect(host.isPrewarmed)
        #expect(host.isVisible)  // a panel on screen, not only machine state
        #expect(host.frame == IslandLayout.frame(.collapsed, on: displays.displays[0]).cgRect)
        #expect(cpu < .milliseconds(50))
        #expect(signposts.begun == ["drop→island"])
        #expect(signposts.ended == ["drop→island"])
    }

    @Test func aDropWithNoDisplayStillEndsItsSignpost() throws {
        let displays = FakeDisplayProvider([])
        let hosts = IslandHosts(provider: displays)
        defer { hosts.close() }
        let signposts = RecordingSignposts()
        let hud = NotchHUD(hosts: hosts, provider: displays, signposts: signposts)
        hud.prepare(near: nil)
        hud.show(try HUDFx.snapshot(submitted: 1))
        #expect(hosts.panelsBuilt == 0)
        #expect(hosts.visibleDisplays.isEmpty)
        #expect(signposts.begun == ["drop→island"])
        #expect(signposts.ended == signposts.begun)
    }

    @Test func theCPUMeasureLeavesOutTimeSpentWaiting() {
        let cpu = ThreadCPUTime.measure { Thread.sleep(forTimeInterval: 0.1) }
        #expect(cpu < .milliseconds(20))
    }
}

/// Records the HUD's signpost intervals by name.
@MainActor
final class RecordingSignposts: HUDSignposting {
    private(set) var begun: [String] = []
    private(set) var ended: [String] = []

    func begin(_ name: StaticString) -> HUDSignpostInterval {
        begun.append("\(name)")
        return HUDSignpostInterval(name: name, state: nil)
    }

    func end(_ interval: HUDSignpostInterval) { ended.append("\(interval.name)") }
}

import AppKit
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletTrigger

@testable import ZivletBox

@Suite("Tray drop target appears quickly (design/19 §9 budget: ≤ 50 ms)")
@MainActor
struct TrayTimingTests {
    @Test func theDropTargetShowsWithin50ms() throws {
        let displays = try FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: displays)  // as the app builds it: pre-warmed per display (D-N8, D-N9)
        defer { hosts.close() }
        let box = FakeTrayBox(count: 12)
        let tray = TrayClient(hosts: hosts, box: box, opensWhileDragging: { true })
        hosts.register(tray, as: .tray)
        let driver = TrayDriver(
            tray: tray, zones: TrayDriver.zones(for: displays.displays), shakeToOpen: { false },
            openForShake: { _ in }, itemCount: { _ in 3 })
        let housing = try #require(NotchGeometry.housing(of: displays.displays[0]))
        let point = Point2D(x: housing.midX, y: housing.midY)
        let dwell = NotchProximity.Config.provisional.dwell
        let resting = InputSample(
            uptime: .seconds(10), source: .frame, primaryButtonDown: true, dragChangeCount: 1,
            dragHasFileTypes: true, location: point)
        driver.observe(resting)
        let entering = InputSample(
            uptime: .seconds(10) + dwell, source: .frame, primaryButtonDown: true, dragChangeCount: 1,
            dragHasFileTypes: true, location: point)
        let start = ContinuousClock.now  // the clock starts at the sample that completes the dwell
        driver.observe(entering)
        let host = try #require(hosts.host(on: 1))
        #expect(host.isVisible)  // a panel on screen, not only machine state
        #expect(host.frame == IslandLayout.frame(.dropTarget, on: displays.displays[0]).cgRect)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(50), "took \(elapsed)")
    }
}

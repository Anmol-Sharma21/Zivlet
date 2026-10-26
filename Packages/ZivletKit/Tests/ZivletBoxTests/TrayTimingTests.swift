import AppKit
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletTrigger

@testable import ZivletBox

/// The structure is asserted on every attempt; the 50 ms budget on the best of three, since wall-clock time around
/// real AppKit windows depends on the machine's load (the same lesson as the notch HUD timing test, G-M5b-5). The
/// budget on the app's real drag path is the owner's QA row, not this test.
@Suite("Tray drop target appears quickly (design/19 §9 budget: ≤ 50 ms)")
@MainActor
struct TrayTimingTests {
    static let attempts = 3

    @Test func theDropTargetShowsWithin50ms() throws {
        var best = Duration.seconds(60)
        for _ in 0..<Self.attempts {
            best = min(best, try Self.showDropTarget())
            if best < .milliseconds(50) { break }
        }
        #expect(best < .milliseconds(50), "best of \(Self.attempts): \(best)")
    }

    /// Builds the hosts as the app does, completes the dwell, checks the drop target is on screen and returns how
    /// long the last sample took to put it there.
    static func showDropTarget() throws -> Duration {
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
        driver.observe(sample(at: .seconds(10), point))
        let start = ContinuousClock.now  // the clock starts at the sample that completes the dwell
        driver.observe(sample(at: .seconds(10) + dwell, point))
        let host = try #require(hosts.host(on: 1))
        let elapsed = ContinuousClock.now - start
        #expect(host.isVisible)  // a panel on screen, not only machine state
        #expect(host.frame == IslandLayout.frame(.dropTarget, on: displays.displays[0]).cgRect)
        return elapsed
    }

    static func sample(at uptime: Duration, _ point: Point2D) -> InputSample {
        InputSample(
            uptime: uptime, source: .frame, primaryButtonDown: true, dragChangeCount: 1, dragHasFileTypes: true,
            location: point)
    }
}

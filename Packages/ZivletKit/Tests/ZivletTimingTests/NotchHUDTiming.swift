import AppKit
import Foundation
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime
import ZivletUI

/// P1-40's wall-clock budget (a drop shows its HUD in ≤ 50 ms), judged by `make timing` below the load limit
/// (D-M7-3, D-M7-4). Each of 20 drops gets fresh, pre-warmed hosts, as the app has at launch; the clock runs from
/// `prepare` to the island on screen. The first drop in the process is cold (the island's content draws for the
/// first time) and is judged on its own: P1-40's 50 ms is a known issue for it (OS-M7-12), and a stated first-drop
/// ceiling of 150 ms fails it (D-M7-65). Every later drop must meet the budget. p50, p95 and the slowest are printed.
@Suite("Notch HUD drop → island wall time", .enabled(if: TimingGate.isEnabled()), .serialized)
@MainActor
struct NotchHUDTiming {
    static let drops = 20
    static let budget = Duration.milliseconds(50)
    /// The cold first drop of a process: 23-94 ms measured at loads up to 2.94; 150 ms leaves room for that spread and
    /// still fails a first-drop regression. Not a product budget: the app's own first drop is judged at 50 ms by m5a X2.
    static let firstDropCeiling = Duration.milliseconds(150)

    @Test func everyDropShowsTheIslandWithin50ms() throws {
        let samples = try (0..<Self.drops).map { _ in try Self.oneDrop() }
        let first = samples[0]
        let warm = Durations(Array(samples.dropFirst()))
        let p50 = try warm.percentile(50)
        let p95 = try warm.percentile(95)
        let slowest = try warm.percentile(100)
        TimingGate.report(
            "drop→island first (cold) \(TimingGate.milliseconds(first)); warm p50 \(TimingGate.milliseconds(p50)), "
                + "p95 \(TimingGate.milliseconds(p95)), max \(TimingGate.milliseconds(slowest)) of 50 ms "
                + "(\(Self.drops - 1) drops)")
        #expect(slowest <= Self.budget)
        // G-M7-10, OS-M7-12: the cold first drop measured 23-94 ms here (warm drops 3-5 ms). The budget is not
        // changed; the app's own first drop is judged by m5a X2 from its signpost. Known and printed until the owner
        // decides (draw the island's content once at launch, or a separate first-drop budget), never hidden.
        withKnownIssue("the cold first drop can exceed 50 ms (OS-M7-12)", isIntermittent: true) {
            #expect(first <= Self.budget)
        }
        #expect(first <= Self.firstDropCeiling, "the cold first drop passed its 150 ms ceiling")
    }

    private static func oneDrop() throws -> Duration {
        let displays = try FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: displays)
        defer { hosts.close() }
        let hud = NotchHUD(hosts: hosts, provider: displays)
        let snapshot = try oneQueuedItem()
        let start = ContinuousClock.now
        hud.prepare(near: CGPoint(x: -4500, y: -4500))
        hud.show(snapshot)
        let elapsed = ContinuousClock.now - start
        #expect(try #require(hosts.host(on: 1)).isVisible)
        return elapsed
    }

    private static func oneQueuedItem() throws -> BatchSnapshot {
        let input = try InputItem(url: URL(filePath: "/tmp/photo.heic"), format: .heic, byteCount: 1_000)
        let request = try JobRequest(input: input, operation: .convert(.png), destination: URL(filePath: "/tmp"))
        return BatchSnapshot(batch: BatchID(), target: .png, plan: RequestPlan(requests: [request], rejections: []))
    }
}

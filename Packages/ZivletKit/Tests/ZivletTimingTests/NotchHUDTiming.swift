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
/// `prepare` to the island on screen. Every drop must meet the budget; p50, p95 and the slowest are printed.
@Suite("Notch HUD drop → island wall time", .enabled(if: TimingGate.isEnabled()), .serialized)
@MainActor
struct NotchHUDTiming {
    static let drops = 20
    static let budget = Duration.milliseconds(50)

    @Test func everyDropShowsTheIslandWithin50ms() throws {
        let samples = try (0..<Self.drops).map { _ in try Self.oneDrop() }
        let durations = Durations(samples)
        let p50 = try durations.percentile(50)
        let p95 = try durations.percentile(95)
        let slowest = try durations.percentile(100)
        TimingGate.report(
            "drop→island p50 \(TimingGate.milliseconds(p50)), p95 \(TimingGate.milliseconds(p95)), "
                + "max \(TimingGate.milliseconds(slowest)) of 50 ms (\(Self.drops) drops)")
        #expect(slowest <= Self.budget)
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

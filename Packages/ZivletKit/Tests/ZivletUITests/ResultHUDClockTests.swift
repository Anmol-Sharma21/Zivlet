import AppKit
import NotchTestSupport
import Testing
import ZivletCore

@testable import ZivletUI

@Suite("ResultHUD lingers survive system sleep (D-N11)")
@MainActor
struct ResultHUDClockTests {
    @Test func aWakeBeforeTheDeadlineReschedulesAndTheCardStillLeaves() async throws {
        let clock = ManualClock()  // sleeps return when the test advances it, or early once with wakeEarly
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] }, clock: clock)
        hud.show(try HUDFx.finished(outputs: [("a.png", before: 1, after: 1)], target: .png))
        #expect(await eventually { clock.pendingSleepers == 1 })
        await clock.wakeEarly(by: .seconds(1))  // the first sleep ends 1 s before the deadline
        #expect(hud.isVisible)  // not yet expired: rescheduled, not dropped
        #expect(clock.pendingSleepers == 1)
        await clock.advance(by: .seconds(1))
        #expect(!hud.isVisible)
    }

    @Test func aLingerThatSpansSleepHasPassedOnWake() async throws {
        let clock = ManualClock()
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] }, clock: clock)
        hud.show(try HUDFx.finished(outputs: [("a.png", before: 1, after: 1)], target: .png))
        #expect(await eventually { clock.pendingSleepers == 1 })
        await clock.advance(by: .seconds(60))  // the Mac slept for a minute; the clock kept counting
        #expect(!hud.isVisible)
    }
}

/// Waits (by turns of the main actor) until `condition` holds, for at most about a second.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

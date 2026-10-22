import AppKit
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotchCore

@testable import ZivletNotch

@Suite("Island host (P2-115)")
@MainActor
struct IslandHostTests {
    @Test func showingDoesNotTakeTheKeyWindow() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.isVisible && !host.isKey)
        host.close()
    }

    @Test func expandingSetsTheLargerFrameBeforeTheAnimation() throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display, motion: .slow(0.2))
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        #expect(host.frame == IslandLayout.frame(.expanded, on: display, contentHeight: 108).cgRect)
        host.close()
    }

    @Test func collapsingShrinksTheFrameWhenTheAnimationCompletes() async throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display, motion: .slow(0.05))
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.frame == IslandLayout.frame(.expanded, on: display, contentHeight: 108).cgRect)
        await host.animationsSettled()
        #expect(host.frame == IslandLayout.frame(.collapsed, on: display).cgRect)
        host.close()
    }

    @Test func aShowDuringTheFadeOutKeepsThePanelVisible() async throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display, motion: .slow(0.2))
        host.apply([.show(.toast, display: 1, contentHeight: 0)])
        host.apply([.hide])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])  // a new job during the fade
        await host.animationsSettled()
        #expect(host.isVisible && host.frame == IslandLayout.frame(.collapsed, on: display).cgRect)
        host.close()
    }

    @Test func anExpandDuringACollapseKeepsTheLargeFrame() async throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display, motion: .slow(0.1))
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        await host.animationsSettled()
        #expect(host.frame == IslandLayout.frame(.expanded, on: display, contentHeight: 108).cgRect)
        #expect(host.surface == .expanded)
        host.close()
    }

    @Test func hiddenOrdersOutAndLeavesNoPendingTask() async throws {
        let clock = ManualClock()
        let host = makeHost(try OffscreenDisplays.notch(), clock: clock)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0), .schedule(.seconds(10))])
        #expect(host.hasPendingDeadline)
        host.apply([.hide, .cancelDeadline])
        await host.animationsSettled()
        #expect(!host.isVisible && !host.hasPendingDeadline && !host.hasPendingAnimation)
        #expect(clock.pendingSleepers == 0)
    }

    @Test func aDeadlineFeedsOneTickToTheMachine() async throws {
        let clock = ManualClock()
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), clock: clock, log: log)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        log.clear()
        host.apply([.schedule(.milliseconds(10))])
        await clock.advance(by: .milliseconds(10))
        #expect(log.events == [.tick(now: .milliseconds(10))])
        await clock.advance(by: .seconds(1))
        #expect(log.events.count == 1 && !host.hasPendingDeadline)
        host.close()
    }

    @Test func aSleepThatWakesEarlyReschedules() async throws {
        let clock = ManualClock()
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), clock: clock, log: log)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        log.clear()
        host.apply([.schedule(.seconds(2))])
        #expect(await eventually { clock.pendingSleepers == 1 })  // the deadline task is asleep
        await clock.wakeEarly(by: .milliseconds(500))
        #expect(log.events.isEmpty && host.hasPendingDeadline && clock.pendingSleepers == 1)
        await clock.advance(by: .milliseconds(500))
        #expect(log.events == [.tick(now: .seconds(2))])
        host.close()
    }

    @Test func aNewScheduleReplacesTheOldOne() async throws {
        let clock = ManualClock()
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), clock: clock, log: log)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        log.clear()
        host.apply([.schedule(.seconds(1))])
        host.apply([.schedule(.seconds(3))])
        await clock.advance(by: .seconds(2))
        #expect(log.events.isEmpty && clock.pendingSleepers == 1)
        await clock.advance(by: .seconds(1))
        #expect(log.events == [.tick(now: .seconds(3))])
        host.close()
    }

    @Test func aContentChangeSendsTheMeasuredHeight() throws {
        let client = FakeClient()
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), client: client, log: log)
        host.contentChanged()
        let first = log.events.compactMap(Self.height)
        #expect(first.count == 1 && (first.first ?? 0) > 20)
        host.contentChanged()
        #expect(log.events.compactMap(Self.height).count == 1)  // unchanged: nothing sent
        client.lines = 6
        host.contentChanged()
        let heights = log.events.compactMap(Self.height)
        #expect(heights.count == 2 && heights[1] > heights[0])
        host.close()
    }

    @Test func theHostIsPrewarmed() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        #expect(host.isPrewarmed && !host.isVisible)
        host.close()
    }

    @Test func thePillIsUsedOnADisplayWithoutANotch() throws {
        let display = try OffscreenDisplays.plain()
        let host = makeHost(display)
        host.apply([.show(.collapsed, display: 2, contentHeight: 0)])
        #expect(host.frame.size == CGSize(width: 200, height: 28))
        #expect(host.frame == IslandLayout.frame(.collapsed, on: display).cgRect)
        host.close()
    }

    @Test func newGeometryUnderTheSameIDReLaysOutTheCurrentSurface() throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        let moved = try DisplayFixtures.moved(display, dx: -300, dy: 0)
        host.update(display: moved)
        #expect(host.frame == IslandLayout.frame(.collapsed, on: moved).cgRect)
        host.close()
    }

    @Test func becomingKeyAndEscapeReachTheMachine() throws {
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), log: log)
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        log.clear()
        host.panelDidBecomeKey()
        host.panelDidResignKey()
        host.panelEscape()
        #expect(log.kinds == [.clicked, .resignedKey, .escape])
        host.close()
    }

    static func height(_ event: IslandEvent) -> Double? {
        if case .contentHeightChanged(let h, _) = event { return h }
        return nil
    }
}

import AppKit
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotchCore

@testable import ZivletNotch

@Suite("Island host hover (D-N6)")
@MainActor
struct IslandHostHoverTests {
    @Test func theTrackingAreaFollowsTheShapeNotTheWindow() async throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display, motion: .slow(0.2))
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])  // the frame stays large while the shape shrinks
        let collapsed = IslandLayout.frame(.collapsed, on: display).cgRect
        #expect(host.frame.size != collapsed.size)
        #expect(host.trackingRectOnScreen == collapsed)
        await host.animationsSettled()
        #expect(host.trackingRectOnScreen == collapsed && host.frame == collapsed)
        host.close()
    }

    @Test func aFrameShrinkUnderAStillPointerSendsExit() async throws {
        let display = try OffscreenDisplays.notch()
        let pointer = FakePointer()
        let log = EventLog()
        let host = makeHost(display, pointer: pointer, log: log)
        let expanded = IslandLayout.frame(.expanded, on: display, contentHeight: 200).cgRect
        pointer.location = CGPoint(x: expanded.midX, y: expanded.minY + 10)  // inside the card, below the tab
        host.apply([.show(.expanded, display: 1, contentHeight: 200)])
        #expect(log.kinds == [.pointerEntered])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        await host.animationsSettled()
        #expect(log.kinds == [.pointerEntered, .pointerExited])
        host.close()
    }

    @Test func anIslandAppearingUnderAStillPointerSendsEnter() throws {
        let display = try OffscreenDisplays.notch()
        let pointer = FakePointer()
        let log = EventLog()
        let host = makeHost(display, pointer: pointer, log: log)
        let collapsed = IslandLayout.frame(.collapsed, on: display).cgRect
        pointer.location = CGPoint(x: collapsed.midX, y: collapsed.minY + 4)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(log.kinds == [.pointerEntered])
        host.close()
    }

    @Test func aPointerOutsideSendsNothingAtShow() throws {
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), log: log)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(log.events.isEmpty)
        host.close()
    }

    @Test func enterIsIgnoredWhileACollapseRuns() async throws {
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), motion: .slow(0.2), log: log)
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        host.trackingEntered()
        #expect(log.events.isEmpty)
        await host.animationsSettled()
        host.trackingEntered()
        host.trackingExited()
        host.trackingExited()  // a second exit without an enter is not sent again
        #expect(log.kinds == [.pointerEntered, .pointerExited])
        host.close()
    }

    @Test func accessibilityFocusReachesTheMachine() throws {
        let log = EventLog()
        let host = makeHost(try OffscreenDisplays.notch(), log: log)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        host.accessibilityFocusChanged(true)
        host.accessibilityFocusChanged(false)
        #expect(log.kinds == [.accessibilityFocused, .accessibilityUnfocused])
        host.close()
    }

    @Test func heldAndCloseEffectsGoToTheClient() throws {
        let client = FakeClient()
        let host = makeHost(try OffscreenDisplays.notch(), client: client)
        host.apply([.show(.expanded, display: 1, contentHeight: 108), .held(true)])
        host.apply([.held(false), .closeRequested(.hud)])
        #expect(client.held == [true, false] && client.closed == [1])
        host.close()
    }

    @Test func theAccessibilityActionAsksTheClient() throws {
        let client = FakeClient()
        let host = makeHost(try OffscreenDisplays.notch(), client: client)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        host.performAccessibilityAction()
        #expect(client.actions == 1)
        #expect(host.accessibility.label == "Fake island" && host.accessibility.value == "3 lines")
        host.close()
    }
}

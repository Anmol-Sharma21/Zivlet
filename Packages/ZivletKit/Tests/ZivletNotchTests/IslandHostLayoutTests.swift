import AppKit
import NotchTestSupport
import Synchronization
import Testing
import ZivletCore
import ZivletNotchCore

@testable import ZivletNotch

@Suite("Island host: geometry changes, motion and accessibility text")
@MainActor
struct IslandHostLayoutTests {
    @Test func newGeometryUnderTheSameIDRefreshesTheInsetAndTheCorners() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.chrome.contentTopInset == 38 && host.chrome.topRadius == 0)
        let plain = try DisplayFixtures.moved(try OffscreenDisplays.plain(), dx: 0, dy: 0, id: 1)
        host.update(display: plain)
        let pill = IslandLayout.frame(.collapsed, on: plain).cgRect
        #expect(host.chrome.contentTopInset == 0 && host.chrome.topRadius == pill.height / 2)
        host.close()
    }

    @Test func theCornersAndTheFlareFollowTheSurface() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.chrome.bottomRadius == 12 && host.chrome.flare == 6 && host.chrome.topRadius == 0)
        host.apply([.show(.toast, display: 1, contentHeight: 0)])
        #expect(host.chrome.bottomRadius == 18)
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        #expect(host.chrome.bottomRadius == 24)
        host.close()
    }

    @Test func thePillHasNoFlare() throws {
        let host = makeHost(try OffscreenDisplays.plain())
        host.apply([.show(.toast, display: 2, contentHeight: 0)])
        #expect(host.chrome.flare == 0 && host.chrome.topRadius == host.chrome.bottomRadius)
        host.close()
    }

    @Test func theHostSetsTheFinishPerSurface() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.chrome.finish == .black(outline: false))
        host.apply([.show(.toast, display: 1, contentHeight: 0)])
        #expect(host.chrome.finish == .glass(band: 38))
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        #expect(host.chrome.finish == .glass(band: 38))
        host.close()
    }

    @Test func thePillIsGlassWithoutABand() throws {
        let host = makeHost(try OffscreenDisplays.plain())
        host.apply([.show(.collapsed, display: 2, contentHeight: 0)])
        #expect(host.chrome.finish == .glass(band: 0))
        host.close()
    }

    /// A card can stay open for a long time (a failure lingers until closed), so a new setting changes the island
    /// that is showing, not only the next surface.
    @Test func reduceTransparencyTurnsTheShownGlassSolidAtOnce() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        #expect(host.chrome.finish == .glass(band: 38))
        host.finishSettings = IslandFinish.Settings(reduceTransparency: true, increaseContrast: false)
        #expect(host.chrome.finish == .solid(band: 38, outline: false))
        host.finishSettings = .standard
        #expect(host.chrome.finish == .glass(band: 38))
        host.close()
    }

    @Test func aHiddenIslandTakesTheNewSettingAtItsNextSurface() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        let before = host.chrome.finish
        host.finishSettings = IslandFinish.Settings(reduceTransparency: false, increaseContrast: true)
        #expect(host.chrome.finish == before)
        host.apply([.show(.toast, display: 1, contentHeight: 0)])
        #expect(host.chrome.finish == .solid(band: 38, outline: true))
        host.close()
    }

    @Test func increaseContrastOutlinesTheTabAndTurnsTheCardSolid() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.finishSettings = IslandFinish.Settings(reduceTransparency: false, increaseContrast: true)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.chrome.finish == .black(outline: true))
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        #expect(host.chrome.finish == .solid(band: 38, outline: true) && host.chrome.finish.outlined)
        host.close()
    }

    @Test func aHidingIslandKeepsItsFinishWhileItFades() async throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.apply([.show(.toast, display: 1, contentHeight: 0)])
        host.apply([.hide])
        #expect(host.chrome.finish == .glass(band: 38))
        await host.animationsSettled()
        host.close()
    }

    @Test func aShrinkInFlightEndsAtTheNewGeometry() async throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display, motion: .slow(0.05))
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        let moved = try DisplayFixtures.moved(display, dx: -300, dy: 0)
        host.update(display: moved)
        await host.animationsSettled()
        let collapsed = IslandLayout.frame(.collapsed, on: moved).cgRect
        #expect(host.frame == collapsed && host.drawnShapeOnScreen == collapsed)
        host.close()
    }

    @Test func theDrawnShapeStaysPutWhenThePanelGrowsAroundIt() throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        let collapsed = IslandLayout.frame(.collapsed, on: display).cgRect
        #expect(host.drawnShapeOnScreen == collapsed)
        let expanded = IslandLayout.frame(.expanded, on: display, contentHeight: 108).cgRect
        host.setPanelFrame(collapsed.union(expanded))
        #expect(host.drawnShapeOnScreen == collapsed)
        host.close()
    }

    @Test func underReduceMotionACollapseReachesItsFrameInTheSameTurn() throws {
        let display = try OffscreenDisplays.notch()
        let host = makeHost(display, motion: .motion)
        host.curves = IslandMotion(reduceMotion: true)
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        let collapsed = IslandLayout.frame(.collapsed, on: display).cgRect
        #expect(host.frame == collapsed && host.drawnShapeOnScreen == collapsed)
        host.close()
    }

    @Test func theAccessibilityTextIsRefreshedWithoutANewSurface() throws {
        let client = FakeClient()
        let host = makeHost(try OffscreenDisplays.notch(), client: client)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.accessibilityValue == "3 lines")
        client.lines = 5
        host.refreshAccessibility()
        #expect(host.accessibilityValue == "5 lines")
        host.close()
    }

    @Test func aNewSpokenValueDoesNotInvalidateTheChrome() throws {
        let client = FakeClient()
        let host = makeHost(try OffscreenDisplays.notch(), client: client)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        let invalidated = Mutex(false)
        withObservationTracking {
            _ = IslandChrome(model: host.chrome, accessibility: host.accessibility).body
            _ = host.chrome.shapeRect
            _ = host.chrome.content
            _ = host.chrome.surface
            _ = host.chrome.opacity
            _ = host.chrome.topRadius
            _ = host.chrome.bottomRadius
            _ = host.chrome.flare
            _ = host.chrome.finish
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        client.lines = 5
        host.refreshAccessibility()
        #expect(!invalidated.withLock { $0 } && host.accessibility.value == "5 lines")
        host.close()
    }

    @Test func aPointerOnTheTopEdgeOfTheScreenIsInside() throws {
        let display = try OffscreenDisplays.notch()
        let pointer = FakePointer()
        let log = EventLog()
        let host = makeHost(display, pointer: pointer, log: log)
        let collapsed = IslandLayout.frame(.collapsed, on: display).cgRect
        pointer.location = CGPoint(x: collapsed.midX, y: collapsed.maxY)
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(log.kinds == [.pointerEntered])
        host.close()
    }
}

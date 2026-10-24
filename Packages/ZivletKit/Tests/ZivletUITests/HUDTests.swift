import AppKit
import SwiftUI
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

@Suite("HUD layout (P1-40, 03a §4.5)")
struct HUDLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func anchorsNearThePointerInsideTheScreen() {
        let frame = HUDLayout.frame(anchor: CGPoint(x: 1430, y: 5), index: 0, screen: screen)
        #expect(frame.size == CGSize(width: 360, height: 108))
        #expect(frame.maxX <= screen.maxX - 12 && frame.minY >= screen.minY + 12)
    }

    @Test func concurrentBatchesCascade24Points() {
        let a = HUDLayout.frame(anchor: CGPoint(x: 400, y: 400), index: 0, screen: screen)
        let b = HUDLayout.frame(anchor: CGPoint(x: 400, y: 400), index: 1, screen: screen)
        #expect(b.minX - a.minX == 24 && a.minY - b.minY == 24)
    }

    @Test func noAnchorMeansTheScreenCentre() {
        let frame = HUDLayout.frame(anchor: nil, index: 0, screen: screen)
        #expect(frame.minX == 736 && frame.maxY == 434)
    }

    @Test func aNewPanelTakesTheLowestFreeCascadeSlot() {
        #expect(HUDLayout.freeSlot(used: []) == 0)
        #expect(HUDLayout.freeSlot(used: [1]) == 0)
        #expect(HUDLayout.freeSlot(used: [0, 1, 3]) == 2)
    }

    @Test func theScreenIsTheOneUnderThePointer() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        #expect(HUDLayout.screen(for: CGPoint(x: -100, y: 100), in: [screen, left]) == left)
        #expect(HUDLayout.screen(for: CGPoint(x: 9_000, y: 100), in: [screen, left]) == screen)
        #expect(HUDLayout.screen(for: nil, in: []) == nil)
    }
}

@Suite("HUD copy (P1-40)")
struct HUDCopyTests {
    @Test func workingLineHasNameIndexCountPercentAndETA() {
        let line = HUDCopy.working(
            name: "clip.mov", index: 2, count: 5, fraction: 0.42, eta: .seconds(70), bytes: nil)
        #expect(line == "clip.mov · 2 of 5 · 42% · about 1 min left")
    }

    @Test func unknownDurationShowsBytes() {
        #expect(
            HUDCopy.working(name: "a.wav", index: 1, count: 1, fraction: nil, eta: nil, bytes: 12_400_000)
                == "a.wav · 12.4 MB written")
    }

    @Test func titleNamesTheTarget() { #expect(HUDCopy.title(target: .webm) == "Converting to WEBM") }

    @Test(arguments: [
        (Duration.seconds(5), "almost done"), (.seconds(42), "less than a minute left"),
        (.seconds(70), "about 1 min left"), (.seconds(400), "about 7 min left"), (.seconds(7_500), "about 2 hr left"),
    ])
    func timeLeftIsRoughOnPurpose(eta: Duration, text: String) {
        #expect(HUDCopy.timeLeft(eta) == text)
    }

    @Test(arguments: [
        (Duration.seconds(5), "almost done"), (.seconds(40), "< 1 min"), (.seconds(190), "3 min"),
        (.seconds(7_400), "2 hr"),
    ])
    func theShortTimeLeftUsesTheSameThresholds(eta: Duration, text: String) {  // 19b §5, the island's working card
        #expect(HUDCopy.shortTimeLeft(eta) == text)
    }

    @Test func aSnapshotGivesTheLineOfItsCurrentItem() throws {
        let progress = JobProgress(fraction: 0.5, eta: .seconds(70))
        #expect(HUDCopy.working(try HUDFx.running(progress)) == "clip.mov · 50% · about 1 min left")
        #expect(HUDCopy.working(try HUDFx.snapshot(submitted: 3)) == "file0.heic · 1 of 3 · 0%")
    }
}

@Suite("HUD appears quickly (P1-40: ≤ 50 ms)")
@MainActor
struct HUDTimingTests {
    @Test func firstFrameWithin50ms() throws {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        let snapshot = try HUDFx.snapshot(submitted: 1)
        let start = ContinuousClock.now
        hud.prepare(near: CGPoint(x: -4000, y: -4000))
        hud.show(snapshot)
        #expect(hud.isVisible)
        #expect(ContinuousClock.now - start < .milliseconds(50))
        hud.close(snapshot.batch)
        #expect(!hud.isVisible)
    }

    @Test func eachConcurrentBatchHasItsOwnCascadedPanel() throws {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        let (a, b) = (try HUDFx.snapshot(submitted: 1), try HUDFx.snapshot(submitted: 2))
        hud.prepare(near: CGPoint(x: -4000, y: -4400))
        hud.show(a)
        hud.prepare(near: CGPoint(x: -4000, y: -4400))
        hud.show(b)
        let frames = hud.panelFrames
        #expect(frames.count == 2)
        #expect(frames[1].minX - frames[0].minX == 24 && frames[0].maxY - frames[1].maxY == 24)
        hud.close(a.batch)
        hud.close(b.batch)
    }

    /// A(0) and B(1) open, A closes: the next batch goes where A was, not on top of B.
    @Test func aNewBatchTakesTheSlotAClosedOneLeft() throws {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        let (a, b, c) = (
            try HUDFx.snapshot(submitted: 1), try HUDFx.snapshot(submitted: 1), try HUDFx.snapshot(submitted: 1)
        )
        for snapshot in [a, b] {
            hud.prepare(near: CGPoint(x: -4000, y: -4400))
            hud.show(snapshot)
        }
        let (frameA, frameB) = (hud.panelFrames[0], hud.panelFrames[1])
        hud.close(a.batch)
        hud.prepare(near: CGPoint(x: -4000, y: -4400))
        hud.show(c)
        #expect(hud.panelFrames == [frameB, frameA])
        hud.close(b.batch)
        hud.close(c.batch)
    }

    /// Every drop, not only the first, finds a panel already built (P1-40: only place and fill on the drop path).
    @Test func theSparePanelIsRebuiltAfterADrop() async throws {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        #expect(hud.hasSpare)
        let snapshot = try HUDFx.snapshot(submitted: 1)
        hud.show(snapshot)
        #expect(!hud.hasSpare)
        for _ in 0..<100 where !hud.hasSpare { await Task.yield() }
        #expect(hud.hasSpare)
        hud.close(snapshot.batch)
    }
}

@Suite("HUD panels can become key (Escape, selectable details)")
@MainActor
struct HUDKeyTests {
    /// A borderless window cannot become key by default; without key status the card's Escape shortcut and its
    /// selectable failure details do nothing.
    @Test func theHUDWindowCanBecomeKeyWithoutActivatingZivlet() {
        let window = HUDWindow(size: HUDLayout.size)
        #expect(window.canBecomeKey && window.styleMask.contains(.nonactivatingPanel))
        #expect(window.styleMask.contains(.borderless) && window.becomesKeyOnlyIfNeeded)
    }

    @Test func theResultPanelUsesTheHUDWindow() {
        let panel = HUDPanel(HUDPanel.Callbacks(cancel: { _ in }, act: { _, _ in }, hover: { _, _ in }))
        #expect(panel.canBecomeKey)
    }
}

@Suite("HUD text contrast over glass (NFR-14)")
struct HUDInkTests {
    /// The glass may let the backdrop through untouched: a white desktop behind dark-mode white text, a black one
    /// behind light-mode black text. Primary and secondary text must still reach 4.5:1.
    @Test(arguments: [ColorScheme.dark, .light])
    func textKeeps4_5To1OverTheWorstBackdrop(scheme: ColorScheme) {
        #expect(HUDInk.worstContrast(scheme: scheme, textOpacity: 1) >= 4.5)
        #expect(HUDInk.worstContrast(scheme: scheme, textOpacity: HUDInk.secondaryOpacity) >= 4.5)
    }

    @Test func theScrimOpposesTheText() {
        #expect(HUDInk.scrim(for: .dark) == Color.black.opacity(HUDInk.scrimOpacity))
        #expect(HUDInk.scrim(for: .light) == Color.white.opacity(HUDInk.scrimOpacity))
    }
}

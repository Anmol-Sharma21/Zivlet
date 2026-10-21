import AppKit
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
}

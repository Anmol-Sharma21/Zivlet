import AppKit
import Testing
import ZivletNotch
import ZivletShelfCore

@testable import ZivletBox

/// Records each fade and holds its completion until `finish()`; `cancel` is recorded too.
@MainActor
final class RecordingFader: PanelFading {
    private(set) var fades: [Double] = []
    private(set) var cancels = 0
    private var completions: [@MainActor @Sendable () -> Void] = []

    func fadeOut(_ panel: NSWindow, seconds: Double, completion: @escaping @MainActor @Sendable () -> Void) {
        fades.append(seconds)
        panel.alphaValue = 0.5
        completions.append(completion)
    }

    func cancel(_ panel: NSWindow) {
        cancels += 1
        panel.alphaValue = 1
    }

    func finish() {
        let pending = completions
        completions = []
        pending.forEach { $0() }
    }
}

@Suite("The Drop Box leaves with opacity (G-M5b-10, 19c D-BL12)")
@MainActor
struct BoxExitTests {
    static func shownBox(_ rig: BoxRig) async throws -> BoxController {
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(2), newBox: false)
        box.showPanel()
        return box
    }

    @Test func hidingFadesBeforeOrderingOut() async throws {
        let rig = try BoxRig()
        let fader = RecordingFader()
        rig.fader = fader
        let box = try await Self.shownBox(rig)
        box.hidePanel()
        #expect(fader.fades == [IslandAnimation.exitSeconds(reduceMotion: false)])
        #expect(box.panel.isVisible && box.presentation.base == .hidden)
        fader.finish()
        #expect(!box.panel.isVisible && box.panel.alphaValue == 1)
    }

    @Test func reduceMotionFadesForEighteenHundredths() async throws {
        let rig = try BoxRig()
        let fader = RecordingFader()
        rig.fader = fader
        rig.reduceMotion = true
        let box = try await Self.shownBox(rig)
        box.hidePanel()
        #expect(fader.fades == [0.18])
        fader.finish()
        #expect(!box.panel.isVisible)
    }

    @Test func aShowDuringTheFadeKeepsThePanel() async throws {
        let rig = try BoxRig()
        let fader = RecordingFader()
        rig.fader = fader
        let box = try await Self.shownBox(rig)
        box.hidePanel()
        box.showPanel()
        #expect(fader.cancels == 1 && box.panel.alphaValue == 1 && box.panel.isVisible)
        fader.finish()
        #expect(box.panel.isVisible)
        box.hidePanel()
        fader.finish()
        #expect(!box.panel.isVisible && fader.fades.count == 2)
    }

    @Test func aHiddenPanelDoesNotFadeAgain() async throws {
        let rig = try BoxRig()
        let fader = RecordingFader()
        rig.fader = fader
        let box = try await Self.shownBox(rig)
        box.hidePanel()
        box.displayOptionsChanged()
        fader.finish()
        box.hidePanel()
        #expect(fader.fades.count == 1)
    }

    @Test func theExitTakesTheCollapseSettleCappedAtSixTenths() {
        let full = IslandAnimation.exitSeconds(reduceMotion: false)
        #expect(full > 0.18 && full <= 0.6)
        #expect(IslandAnimation.exitSeconds(reduceMotion: true) == 0.18)
    }
}

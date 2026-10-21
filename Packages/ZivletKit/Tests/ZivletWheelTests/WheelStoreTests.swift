import AppKit
import Testing
import ZivletCore
import ZivletWheelCore

@testable import ZivletWheel

@Suite("Wheel store: highlight, feedback, notices (03a §2.4, §2.7)")
struct WheelStoreTests {
    let feedback = FakeFeedback()

    func store(notice: Duration = .milliseconds(30)) -> WheelStore {
        WheelStore(feedback: feedback, noticeDuration: notice)
    }

    @Test func presentShowsTheModelCollapsedUntilExpanded() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        #expect(s.model?.mode == .convert && s.theme == .solid && !s.isExpanded)
        s.expand()
        #expect(s.isExpanded)
    }

    /// The view expands once per presentation, after it has rendered the collapsed wheel (0.45 → 1 intro).
    @Test func pendingExpansionRunsOnceForTheCurrentPresentationOnly() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        let first = s.presentation
        s.present(Fixtures.model(.tools), emptyMessage: nil, appearance: Fixtures.appearance)
        s.expandIfPending(first)
        #expect(!s.isExpanded)
        s.expandIfPending(s.presentation)
        #expect(s.isExpanded && s.presentation == first + 1)
    }

    @Test func cancelledOrDismissedPresentationNeverExpands() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.cancelExpansion()
        s.expandIfPending(s.presentation)
        #expect(!s.isExpanded)
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.dismiss()
        s.expandIfPending(s.presentation)
        #expect(!s.isExpanded && s.model == nil)
    }

    @Test func highlightChangeFiresOneFeedbackPerNewSlot() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.pointer(.slot(1))
        s.pointer(.slot(1))
        s.pointer(.hub)
        s.pointer(.slot(2))
        #expect(feedback.events == ["highlight", "highlight"])
        #expect(s.model?.highlighted == 2)
    }

    @Test func pointerWithoutAWheelIsIgnored() {
        let s = store()
        s.pointer(.slot(0))
        #expect(s.model == nil && feedback.events.isEmpty)
    }

    @Test func switchReplacesTheModelAndPlaysTheLevelChange() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.pointer(.slot(0))
        s.switchTo(Fixtures.model(.actions), emptyMessage: nil)
        #expect(s.model?.mode == .actions && s.model?.highlighted == nil)
        #expect(feedback.events == ["highlight", "switch"])
    }

    @Test func rejectShowsANoticeThatClearsItself() async throws {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.reject(message: "No tools for SRT files")
        #expect(s.pillText == "No tools for SRT files" && s.rejectCount == 1)
        #expect(feedback.events == ["reject"])
        #expect(try await eventually { s.pillText == nil })
    }

    @Test func emptyWheelShowsItsReasonInThePill() {
        let s = store()
        let empty = WheelModel(mode: .tools, content: .empty(.noTools(.srt)), idleHubLabel: "a.srt")
        s.present(empty, emptyMessage: "No tools for SRT files", appearance: Fixtures.appearance)
        #expect(s.pillText == "No tools for SRT files")
    }

    @Test func dropAcceptedAndDismissResetEverything() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.expand()
        s.dropAccepted()
        s.dismiss()
        #expect(s.model == nil && !s.isExpanded && s.pillText == nil)
        #expect(feedback.events == ["drop"])
    }

    @Test func systemFeedbackMapsEventsToHapticPatterns() {
        let haptics = FakeHaptics()
        let ticks = TickLog()
        let system = SystemWheelFeedback(performer: haptics, tick: TickSound(isEnabled: true, play: ticks.play))
        system.highlightChanged()
        system.modeSwitched()
        system.rejected()
        system.dropAccepted()
        #expect(haptics.patterns == [.alignment, .levelChange, .generic, .generic])
        #expect(ticks.count == 1)
    }

    @Test func tickSoundIsThrottledAndSilentWhenDisabled() {
        let ticks = TickLog()
        let clock = ManualClock()
        let sound = TickSound(isEnabled: true, now: clock.read, play: ticks.play)
        sound.play()
        clock.advance(.milliseconds(10))
        sound.play()
        clock.advance(.milliseconds(40))
        sound.play()
        #expect(ticks.count == 2)
        let muted = TickSound(isEnabled: false, play: ticks.play)
        muted.play()
        #expect(ticks.count == 2)
    }

    /// P1-42: a mode switch never carries the old wheel's highlight into the new one.
    @Test func switchingModeClearsTheHighlight() throws {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.pointer(.slot(1))
        #expect(s.model?.highlighted == 1)
        let current = try #require(s.model)
        s.switchTo(current.switching(to: .tools, content: Fixtures.model(.tools).content), emptyMessage: nil)
        #expect(s.model?.mode == .tools && s.model?.highlighted == nil)
        #expect(feedback.events == ["highlight", "switch"])
    }

    /// Reduce Motion replaces the morph with an 80 ms fade (03a §2.7).
    @Test func theModeSwitchIsAnEightyMillisecondFadeUnderReduceMotion() {
        #expect(WheelMotion.modeSwitch(reduceMotion: true) == WheelMotion.Step(duration: 0.08, isFade: true))
        #expect(WheelMotion.modeSwitch(reduceMotion: false) == WheelMotion.Step(duration: 0.28, isFade: false))
    }

    @Test func soundOffPlaysNothingAndHapticsStay() {
        let haptics = FakeHaptics()
        let ticks = TickLog()
        let system = SystemWheelFeedback(performer: haptics, tick: TickSound(isEnabled: true, play: ticks.play))
        system.apply(FeedbackSettings(sound: false, haptics: true))
        system.highlightChanged()
        #expect(ticks.count == 0 && haptics.patterns == [.alignment])
    }

    @Test func hapticsOffPerformsNothingAndSoundStays() {
        let haptics = FakeHaptics()
        let ticks = TickLog()
        let system = SystemWheelFeedback(performer: haptics, tick: TickSound(isEnabled: true, play: ticks.play))
        system.apply(FeedbackSettings(sound: true, haptics: false))
        system.highlightChanged()
        system.modeSwitched()
        #expect(ticks.count == 1 && haptics.patterns.isEmpty)
        system.apply(.standard)
        system.rejected()
        #expect(haptics.patterns == [.generic])
    }

    @Test func realTickSoundLoadsTheSynthesizedTone() {
        let sound = TickSound(isEnabled: true)
        #expect(sound.isLoaded)
    }
}

final class TickLog {
    private(set) var count = 0
    func play() { count += 1 }
}

final class ManualClock {
    private var value: Duration = .seconds(1)
    func read() -> Duration { value }
    func advance(_ by: Duration) { value += by }
}

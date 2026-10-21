import AppKit
import Testing
import ZivletCore
import ZivletTrigger

@testable import ZivletTriggerHost

/// Collects signals from the real scheduler.
final class SignalLog {
    private(set) var signals: [TriggerSignal] = []
    func record(_ signal: TriggerSignal) { signals.append(signal) }
    var frames: Int { signals.count { $0 == .event(.frame) } }
}

@Suite("System adapters: real AppKit reads, monitors and timers (P0-40)", .serialized)
struct SystemAdapterTests {
    let pasteboard = NSPasteboard.withUniqueName()

    @Test func readerSeesFileTypesOnlyAfterAFileURLIsWritten() throws {
        let reader = SystemInputReader(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        #expect(!reader.dragHasFileTypes())
        let before = reader.dragChangeCount
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/a.png") as NSURL])
        #expect(reader.dragHasFileTypes())
        #expect(reader.dragChangeCount == pasteboard.changeCount && reader.dragChangeCount > before)
    }

    @Test func readerReportsMonotonicUptimeAndTheInjectedWheelFlag() throws {
        let reader = SystemInputReader(pasteboard: pasteboard, pointerInsideWheel: { true })
        let first = reader.uptime
        #expect(reader.uptime >= first)
        #expect(reader.pointerInsideWheel)
        let modifiers = try #require(Self.bracketed(ModifierMask(NSEvent.modifierFlags)) { reader.modifiers })
        #expect(modifiers.read == modifiers.live)
        let location = try #require(
            Self.bracketed(Point2D(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y)) { reader.location })
        #expect(location.read == location.live)
        let button = try #require(Self.bracketed(NSEvent.pressedMouseButtons & 1 == 1) { reader.primaryButtonDown })
        #expect(button.read == button.live)
    }

    /// The pointer and keys are live while tests run, so a reader value only counts when the OS reports the same
    /// value just before and just after it. Retries a few times; nil means the input never held still.
    static func bracketed<Value: Equatable>(
        _ live: @autoclosure () -> Value, attempts: Int = 50, read: () -> Value
    ) -> (live: Value, read: Value)? {
        for _ in 0..<attempts {
            let before = live()
            let value = read()
            if live() == before { return (before, value) }
        }
        return nil
    }

    @Test func schedulerInstallsAndRemovesMonitorsPerPlan() {
        let scheduler = SystemTriggerScheduler()
        scheduler.apply(SamplingPlan(events: [.mouseDown, .mouseDragged, .mouseUp]))
        #expect(scheduler.installedEvents == [.mouseDown, .mouseDragged, .mouseUp])
        scheduler.apply(SamplingPlan(events: [.mouseDown]))
        #expect(scheduler.installedEvents == [.mouseDown])
        scheduler.apply(.off)
        #expect(scheduler.installedEvents.isEmpty)
    }

    @Test func samplerDeliversFramesUntilStopped() async throws {
        let log = SignalLog()
        let scheduler = SystemTriggerScheduler()
        scheduler.onSignal = { log.record($0) }
        scheduler.apply(SamplingPlan(events: [], sampling: true))
        try await Task.sleep(for: .milliseconds(150))
        scheduler.apply(.off)
        let frames = log.frames
        #expect(frames >= 3)
        try await Task.sleep(for: .milliseconds(60))
        #expect(log.frames == frames)
    }

    @Test func timerFallbackRunsWhenNoScreenIsAvailable() async throws {
        let sampler = FrameSampler(fallbackInterval: .milliseconds(10))
        let log = SignalLog()
        sampler.onFrame = { log.record(.event(.frame)) }
        sampler.start(on: nil)
        #expect(sampler.isRunning)
        try await Task.sleep(for: .milliseconds(100))
        sampler.stop()
        #expect(!sampler.isRunning && log.frames >= 3)
    }

    @Test func watchdogTicksWhileOn() async throws {
        let log = SignalLog()
        let scheduler = SystemTriggerScheduler(watchdogInterval: .milliseconds(20))
        scheduler.onSignal = { log.record($0) }
        scheduler.apply(SamplingPlan(events: [], watchdog: true))
        try await Task.sleep(for: .milliseconds(120))
        scheduler.apply(.off)
        #expect(log.frames >= 2)
    }

    @Test func spaceChangeNotificationBecomesASignal() {
        let log = SignalLog()
        let scheduler = SystemTriggerScheduler()
        scheduler.onSignal = { log.record($0) }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        #expect(log.signals == [.spaceChanged])
    }

    @Test func escapeHotkeyRegistersOnlyWhilePlanned() {
        let scheduler = SystemTriggerScheduler()
        scheduler.apply(SamplingPlan(events: [], escapeHotkey: true))
        #expect(scheduler.escapeRegistered)
        scheduler.apply(.off)
        #expect(!scheduler.escapeRegistered)
    }

    /// The system refuses a second Esc hot key in the same process; the scheduler logs it and carries on.
    @Test func refusedEscapeHotkeyLeavesNothingRegistered() {
        let first = EscapeHotkey()
        #expect(first.register())
        let scheduler = SystemTriggerScheduler()
        scheduler.apply(SamplingPlan(events: [], escapeHotkey: true))
        #expect(!scheduler.escapeRegistered)
        let second = EscapeHotkey()
        #expect(!second.register() && !second.isRegistered)
        first.unregister()
        scheduler.apply(.off)
    }

    @Test func escapeHandlerForwardsAPress() {
        let log = SignalLog()
        let scheduler = SystemTriggerScheduler()
        scheduler.onSignal = { log.record($0) }
        scheduler.escapeHotkey.onPress()
        #expect(log.signals == [.escape])
    }
}

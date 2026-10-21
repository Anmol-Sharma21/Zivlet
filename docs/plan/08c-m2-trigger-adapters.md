# 08c — M2 task 6: AppKit trigger adapters

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 6 — System adapters: reads, monitors, display link, watchdog, Esc, Space change (P0-40)

| Field | Value |
|---|---|
| Goal | The real implementations of Task 5's ports. `SystemInputReader`: permission-free reads only (modifier flags, `pressedMouseButtons`, drag-pasteboard change count and **types**, mouse location). `SystemTriggerScheduler`: global + local `NSEvent` monitors per `SamplingPlan.events`, the frame sampler, a 2 Hz watchdog `Timer`, the Esc hot key and the `activeSpaceDidChange` observer, all reported as `TriggerSignal`s on the main actor |
| 05 rows | P0-40; instruments for spikes P-T1 (monitors during real drags) and P-T3 (Esc) of P0-31 |
| Sources | 03a §1.2 (inputs), §1.3 (monitors), §1.5 (rates), §1.8 (Esc, `flagsChanged`), 14 §1.2 B/C/D, §1.3 steps 1–6, §1.4 (local monitor for our own windows) |

| Adapter | API | Permission |
|---|---|---|
| Modifiers | `NSEvent.modifierFlags` → `ModifierMask` (⌃⌥⇧⌘ only) | none |
| Button | `NSEvent.pressedMouseButtons & 1` | none |
| Change count / file types | `NSPasteboard(name: .drag).changeCount`, `availableType(from: [.fileURL] + promise types)` | none (types only, no URL reads) |
| Location | `NSEvent.mouseLocation` (global, y up) | none |
| Mouse monitors | `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents` for left down/dragged/up | none (14 §1.2 B) |
| Sampler | `NSScreen.displayLink(target:selector:)` on the screen under the pointer; `Timer` fallback without a screen | none |
| Esc | Carbon `RegisterEventHotKey(kVK_Escape, 0, …)` only while the wheel is visible; failure is logged, other cancels still work | none expected; spike P-T3 confirms (index D-M2-8) |
| Space change | `NSWorkspace.activeSpaceDidChangeNotification` | none |
| `flagsChanged` | global monitor, only in Debug builds with `-ZivletFlagsMonitor YES` (index D-M2-9) | unknown: spike P-T2 |

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletTriggerHost/SystemInputReader.swift` |
| create | `Sources/ZivletTriggerHost/FrameSampler.swift` (also `Duration.timeInterval`) |
| create | `Sources/ZivletTriggerHost/EscapeHotkey.swift` |
| create | `Sources/ZivletTriggerHost/SystemTriggerScheduler.swift` |
| create | `Tests/ZivletTriggerHostTests/SystemAdapterTests.swift` |

### 6.1 Failing tests first

These tests use real AppKit objects: a uniquely named pasteboard, real monitors, a real display link (and the timer
fallback), a real Carbon hot key, and a posted Space-change notification. The suite is `.serialized`. Run it in a
logged-in session (index §4).

`Packages/ZivletKit/Tests/ZivletTriggerHostTests/SystemAdapterTests.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger
import Testing

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

    @Test func readerReportsMonotonicUptimeAndTheInjectedWheelFlag() {
        let reader = SystemInputReader(pasteboard: pasteboard, pointerInsideWheel: { true })
        let first = reader.uptime
        #expect(reader.uptime >= first)
        #expect(reader.pointerInsideWheel)
        #expect(reader.modifiers == ModifierMask(NSEvent.modifierFlags))
        #expect(reader.location == Point2D(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y))
        #expect(reader.primaryButtonDown == (NSEvent.pressedMouseButtons & 1 == 1))
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

    @Test func escapeHandlerForwardsAPress() {
        let log = SignalLog()
        let scheduler = SystemTriggerScheduler()
        scheduler.onSignal = { log.record($0) }
        scheduler.escapeHotkey.onPress()
        #expect(log.signals == [.escape])
    }
}
```

### 6.2 Run, expect failure

`swift test --filter ZivletTriggerHostTests` → `error: cannot find 'SystemTriggerScheduler' in scope` (also
`SystemInputReader`, `FrameSampler`).

### 6.3 Implement (complete)

`Packages/ZivletKit/Sources/ZivletTriggerHost/SystemInputReader.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger

/// Real OS reads for one sample (03a §1.2). Every read is permission-free: modifier flags, button state, the drag
/// pasteboard's change count and type list, and the global mouse location. No key codes, no URL reads.
public final class SystemInputReader: InputReading {
    /// File URLs plus every file-promise type (Mail, Photos, browsers).
    public static let fileTypes: [NSPasteboard.PasteboardType] =
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    private let pasteboard: NSPasteboard
    private let insideWheel: () -> Bool
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    public init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag), pointerInsideWheel: @escaping () -> Bool = { false }
    ) {
        self.pasteboard = pasteboard
        insideWheel = pointerInsideWheel
        origin = clock.now
    }

    public var uptime: Duration { clock.now - origin }
    public var modifiers: ModifierMask { ModifierMask(NSEvent.modifierFlags) }
    public var primaryButtonDown: Bool { NSEvent.pressedMouseButtons & 1 == 1 }
    public var dragChangeCount: Int { pasteboard.changeCount }
    public var location: Point2D { Point2D(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y) }
    public var pointerInsideWheel: Bool { insideWheel() }

    public func dragHasFileTypes() -> Bool { pasteboard.availableType(from: Self.fileTypes) != nil }
}
```

`Packages/ZivletKit/Sources/ZivletTriggerHost/FrameSampler.swift`:

```swift
import AppKit
import QuartzCore

/// Display-rate ticks while a drag is live (14 §1.3 step 2): `NSScreen.displayLink` on the screen under the pointer
/// (60–120 Hz). Without a screen it falls back to a main-queue timer.
final class FrameSampler: NSObject {
    var onFrame: () -> Void = {}
    private let fallbackInterval: Duration
    private var link: CADisplayLink?
    private var timer: Timer?

    init(fallbackInterval: Duration = .milliseconds(16)) {
        self.fallbackInterval = fallbackInterval
    }

    var isRunning: Bool { link != nil || timer != nil }

    func start(on screen: NSScreen?) {
        guard !isRunning else { return }
        guard let screen else { return startTimer() }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
    }

    /// The screen whose frame holds the pointer, else the main screen.
    static func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    @objc private func tick(_ link: CADisplayLink) { onFrame() }

    private func startTimer() {
        let timer = Timer(timeInterval: fallbackInterval.timeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

extension Duration {
    /// Seconds as `TimeInterval` for `Timer`.
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
```

The Carbon callback is a C function, so it is `nonisolated` and hops back with `MainActor.assumeIsolated` (Carbon
delivers hot keys on the main run loop). The context pointer travels as an integer address because raw pointers are
not `Sendable` under Swift 6 region checking (a direct capture fails with `sending 'context' risks causing data races`).

`Packages/ZivletKit/Sources/ZivletTriggerHost/EscapeHotkey.swift`:

```swift
import Carbon.HIToolbox

/// Esc closes the wheel while it is visible, without Input Monitoring (03a §1.8, spike P-T3): a Carbon hot key that
/// exists only between show and hide. The key is consumed, so Finder's drag continues.
final class EscapeHotkey {
    var onPress: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var isRegistered: Bool { hotKey != nil }

    /// False when the system refuses the key; the caller logs it and the other cancel paths still work.
    @discardableResult
    func register() -> Bool {
        guard hotKey == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), escapePressed, 1, &spec, context, &handler) == noErr
        else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5354_534D), id: 1)  // "STSM"
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            removeHandler()
            return false
        }
        hotKey = ref
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        removeHandler()
    }

    private func removeHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

/// Carbon delivers hot keys on the main run loop. The context travels as an address because raw pointers are not
/// `Sendable`.
private nonisolated func escapePressed(
    _ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    let address = UInt(bitPattern: context)
    guard address != 0 else { return OSStatus(eventNotHandledErr) }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<EscapeHotkey>.fromOpaque(pointer).takeUnretainedValue().onPress()
    }
    return noErr
}
```

AppKit calls monitor handlers, `Timer` blocks and `.main`-queue notification blocks on the main thread;
`MainActor.assumeIsolated` states that to the compiler (and traps if it were ever false). `isolated deinit` (Swift 6.2)
lets the deinitializer tear down monitors on the main actor.

`Packages/ZivletKit/Sources/ZivletTriggerHost/SystemTriggerScheduler.swift`:

```swift
import AppKit
import ZivletTrigger
import os

/// Applies a `SamplingPlan` with real AppKit facilities: global + local `NSEvent` monitors (no permission needed for
/// mouse events, 14 §1.2 B), the frame sampler, a 2 Hz watchdog timer, the Esc hot key, and the Space-change
/// notification. Every callback arrives on the main actor and is forwarded as a `TriggerSignal`.
public final class SystemTriggerScheduler: TriggerScheduling {
    public var onSignal: ((TriggerSignal) -> Void)?

    let escapeHotkey = EscapeHotkey()
    private let sampler = FrameSampler()
    private let watchdogInterval: Duration
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "trigger")
    private var monitors: [MonitoredEvent: [Any]] = [:]
    private var watchdog: Timer?
    private var spaceObserver: (any NSObjectProtocol)?

    public init(watchdogInterval: Duration = .milliseconds(500)) {
        self.watchdogInterval = watchdogInterval
        sampler.onFrame = { [weak self] in self?.emit(.event(.frame)) }
        escapeHotkey.onPress = { [weak self] in self?.emit(.escape) }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.emit(.spaceChanged) } }
    }

    isolated deinit {
        apply(.off)
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    var installedEvents: Set<MonitoredEvent> { Set(monitors.keys) }
    var escapeRegistered: Bool { escapeHotkey.isRegistered }

    public func apply(_ plan: SamplingPlan) {
        updateMonitors(plan.events)
        if plan.sampling { sampler.start(on: FrameSampler.screenUnderPointer()) } else { sampler.stop() }
        setWatchdog(plan.watchdog)
        setEscape(plan.escapeHotkey)
    }

    private func emit(_ signal: TriggerSignal) { onSignal?(signal) }

    private func updateMonitors(_ wanted: Set<MonitoredEvent>) {
        for event in installedEvents.subtracting(wanted) {
            monitors[event]?.forEach(NSEvent.removeMonitor)
            monitors[event] = nil
        }
        for event in wanted.subtracting(installedEvents) { monitors[event] = install(event) }
    }

    /// Global monitors see other apps' events; local monitors see drags that start in our own windows (14 §1.4).
    private func install(_ event: MonitoredEvent) -> [Any] {
        let mask = Self.mask(for: event)
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.event(event.source)) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] nsEvent in
            MainActor.assumeIsolated { self?.emit(.event(event.source)) }
            return nsEvent
        }
        return [global, local].compactMap { $0 }
    }

    private func setWatchdog(_ on: Bool) {
        guard on != (watchdog != nil) else { return }
        watchdog?.invalidate()
        watchdog = nil
        guard on else { return }
        let timer = Timer(timeInterval: watchdogInterval.timeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.event(.frame)) }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func setEscape(_ on: Bool) {
        guard on != escapeHotkey.isRegistered else { return }
        guard on else { return escapeHotkey.unregister() }
        if !escapeHotkey.register() { logger.error("Esc hot key refused; re-tap, hub drop and release still cancel") }
    }

    private static func mask(for event: MonitoredEvent) -> NSEvent.EventTypeMask {
        switch event {
        case .mouseDown: .leftMouseDown
        case .mouseDragged: .leftMouseDragged
        case .mouseUp: .leftMouseUp
        case .flagsChanged: .flagsChanged
        }
    }
}
```

### 6.4 Verify green

`swift test --filter ZivletTriggerHostTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 24 tests in 2 suites passed`. `make coverage` → ZivletTriggerHost ≥ 80 % (reference 88 %; the
uncovered lines are the real monitor callbacks and the Carbon callback, exercised by the QA checklist).

### 6.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletTriggerHost Packages/ZivletKit/Tests/ZivletTriggerHostTests
git commit -s -m "feat(trigger): add AppKit monitors, display-link sampler, watchdog and Esc hot key"
```

### 6.6 Notes for the spikes this task instruments

| Spike | How to run it with this build | Record in |
|---|---|---|
| P-T1 | Launch the Debug app, drag from Finder, Mail, Safari and Chrome; Console filter `subsystem:app.zivlet.Zivlet`; System Settings › Privacy shows no Zivlet entry | `docs/plan/spikes/P-T1.md` |
| P-T2 | Debug build: `open Zivlet.app --args -ZivletFlagsMonitor YES`; note any prompt; compare tap latency with and without it | `docs/plan/spikes/P-T2.md` |
| P-T3 | Open the wheel during a Finder drag and press Esc: the wheel closes and the drag continues | `docs/plan/spikes/P-T3.md` |

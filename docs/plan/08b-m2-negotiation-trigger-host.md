# 08b — M2 tasks 4–5: drop negotiation, tick gate, TriggerHost

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 4 — Drag-operation negotiation and highlight tick gate (P0-28)

| Field | Value |
|---|---|
| Goal | Pure `DropNegotiation.operation(offered:hit:hasTarget:)`: on a slice with a target, the first of copy, generic, link, move that the source offers; hub, outside and empty wheels refuse. `DragOperations` mirrors the `NSDragOperation` bits so WheelCore stays AppKit-free. `FeedbackGate`: at most one tick per 35 ms, requests older than 150 ms dropped |
| 05 rows | P0-28; the throttle part of P0-42 |
| Sources | 03a §2.5 (`draggingUpdated` row, "always copy"), 15 C-8, 03a §2.7 (tick: 35 ms, 150 ms) |

**Files:** create `Sources/ZivletWheelCore/DropNegotiation.swift` and
`Tests/ZivletWheelCoreTests/DropNegotiationTests.swift`.

### 4.1 Failing tests first

All 16 combinations of copy/link/generic/move, against slice, hub, outside and a slice without a target.

`Packages/ZivletKit/Tests/ZivletWheelCoreTests/DropNegotiationTests.swift`:

```swift
import ZivletCore
import Testing

@testable import ZivletWheelCore

@Suite("Drag-operation negotiation and feedback gate (P0-28, 03a §2.5, §2.7)")
struct DropNegotiationTests {
    static let masks: [DragOperations] = (0..<16).map { bits in
        let pairs: [(Int, DragOperations)] = [(1, .copy), (2, .link), (4, .generic), (8, .move)]
        return pairs.reduce(into: []) { result, pair in if bits & pair.0 != 0 { result.insert(pair.1) } }
    }

    @Test(arguments: masks)
    func aSliceGetsTheFirstOfCopyGenericLinkMove(offered: DragOperations) {
        let expected = [DragOperations.copy, .generic, .link, .move].first { offered.contains($0) } ?? []
        #expect(DropNegotiation.operation(offered: offered, hit: .slot(0), hasTarget: true) == expected)
    }

    @Test(arguments: masks)
    func hubOutsideAndEmptyWheelRefuse(offered: DragOperations) {
        #expect(DropNegotiation.operation(offered: offered, hit: .hub, hasTarget: true) == [])
        #expect(DropNegotiation.operation(offered: offered, hit: .outside, hasTarget: true) == [])
        #expect(DropNegotiation.operation(offered: offered, hit: .slot(0), hasTarget: false) == [])
    }

    @Test func neverOffersDeleteOrPrivate() {
        let all = DragOperations(rawValue: .max)
        #expect(DropNegotiation.operation(offered: all, hit: .slot(1), hasTarget: true) == .copy)
        #expect(DropNegotiation.operation(offered: [.delete, .private], hit: .slot(1), hasTarget: true) == [])
    }

    @Test func rawValuesMatchTheAppKitBits() {
        #expect(DragOperations.copy.rawValue == 1 && DragOperations.link.rawValue == 2)
        #expect(DragOperations.generic.rawValue == 4 && DragOperations.private.rawValue == 8)
        #expect(DragOperations.move.rawValue == 16 && DragOperations.delete.rawValue == 32)
    }

    @Test func feedbackGateSpacesTicksAndDropsStaleRequests() {
        let gate = FeedbackGate()
        let first = gate.admit(requestedAt: .milliseconds(0), now: .milliseconds(1))
        #expect(first.admitted)
        let tooSoon = first.next.admit(requestedAt: .milliseconds(20), now: .milliseconds(20))
        #expect(!tooSoon.admitted)
        let spaced = tooSoon.next.admit(requestedAt: .milliseconds(36), now: .milliseconds(36))
        #expect(spaced.admitted)
        let stale = spaced.next.admit(requestedAt: .milliseconds(100), now: .milliseconds(251))
        #expect(!stale.admitted && stale.next == spaced.next)
    }
}
```

### 4.2 Run, expect failure

`swift test --filter ZivletWheelCoreTests` → `error: cannot find 'DropNegotiation' in scope` (also `DragOperations`,
`FeedbackGate`).

### 4.3 Implement (complete)

`Packages/ZivletKit/Sources/ZivletWheelCore/DropNegotiation.swift`:

```swift
import ZivletCore

/// Mirror of the `NSDragOperation` bits so the policy stays pure. The shell converts with `rawValue`.
public struct DragOperations: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let copy = DragOperations(rawValue: 1)
    public static let link = DragOperations(rawValue: 2)
    public static let generic = DragOperations(rawValue: 4)
    public static let `private` = DragOperations(rawValue: 8)
    public static let move = DragOperations(rawValue: 16)
    public static let delete = DragOperations(rawValue: 32)
}

/// 03a §2.5 / 15 C-8: on a slice with a target, return the first of copy, generic, link, move that the source offers,
/// so a modifier still held at release never blocks the drop. Zivlet always applies copy semantics; the returned
/// operation is only what the drag source shows. Hub, outside and empty wheels refuse.
public enum DropNegotiation {
    static let preference: [DragOperations] = [.copy, .generic, .link, .move]

    public static func operation(offered: DragOperations, hit: HitResult, hasTarget: Bool) -> DragOperations {
        guard case .slot = hit, hasTarget else { return [] }
        return preference.first { offered.contains($0) } ?? []
    }
}

/// Highlight tick throttle (03a §2.7): at most one tick per 35 ms; a request older than 150 ms when it reaches the
/// player is dropped instead of played late.
public struct FeedbackGate: Sendable, Equatable {
    public let minimumSpacing: Duration
    public let staleAfter: Duration
    public let lastPlayed: Duration?

    public init(
        minimumSpacing: Duration = .milliseconds(35), staleAfter: Duration = .milliseconds(150),
        lastPlayed: Duration? = nil
    ) {
        self.minimumSpacing = minimumSpacing
        self.staleAfter = staleAfter
        self.lastPlayed = lastPlayed
    }

    public func admit(requestedAt: Duration, now: Duration) -> (admitted: Bool, next: FeedbackGate) {
        if now - requestedAt > staleAfter { return (false, self) }
        if let lastPlayed, now - lastPlayed < minimumSpacing { return (false, self) }
        return (true, FeedbackGate(minimumSpacing: minimumSpacing, staleAfter: staleAfter, lastPlayed: now))
    }
}
```

### 4.4 Verify green

`swift test --filter ZivletWheelCoreTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 53 tests in 7 suites passed`. Then `make coverage`: ZivletWheelCore 99 %.

### 4.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletWheelCore/DropNegotiation.swift \
        Packages/ZivletKit/Tests/ZivletWheelCoreTests/DropNegotiationTests.swift
git commit -s -m "feat(wheel): add drag-operation negotiation and highlight tick gate"
```

---

## Task 5 — `TriggerHost`: OS ports → `TriggerMachine` → effects (P0-40, logic)

| Field | Value |
|---|---|
| Goal | The host logic of 03a §1.1 behind two protocols, so it is unit-tested with fakes: `InputReading` (every OS read) and `TriggerScheduling` (monitors, sampler, watchdog, Esc). The host builds `InputSample`s, steps the M1 machine, turns monitor/sampler effects plus the machine state into one `SamplingPlan` applied only when it changes, runs the payload probe for `probePayload`, and forwards `show`/`switchTo`/`reject`/`hide` to `onWheelEffect` |
| 05 rows | P0-40 (logic; the AppKit adapters are Task 6) |
| Sources | 03a §1.1–1.5 (states, monitors per state, numbers), 14 §1.3, 02 §6.2 (host is `@MainActor`), index D-M2-11 |

Monitors and timers per state (03a §1.3, §1.5), as the tests assert:

| Machine state | `events` | `sampling` | `watchdog` | `escapeHotkey` |
|---|---|---|---|---|
| idle | mouseDown (+ flagsChanged if enabled) | — | — | — |
| pressed | + mouseDragged, mouseUp | — | 2 Hz | — |
| detecting | mouseDown, mouseUp | on | — | — |
| passive | mouseDown, mouseUp | — | 2 Hz | — |
| live | mouseDown, mouseUp | on | — | — |
| wheel / releasing | mouseDown, mouseUp | on | — | on |

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletTriggerHost/TriggerPorts.swift` — `MonitoredEvent`, `SamplingPlan`, `TriggerSignal`, `InputReading`, `TriggerScheduling` |
| create | `Sources/ZivletTriggerHost/TriggerHost.swift` |
| create | `Sources/ZivletTriggerHost/ModifierMask+AppKit.swift` — `ModifierMask(NSEvent.ModifierFlags)` |
| create | `Tests/ZivletTriggerHostTests/TriggerFakes.swift`, `Tests/ZivletTriggerHostTests/TriggerHostTests.swift` |
| delete | `Sources/ZivletTriggerHost/ZivletTriggerHostPlaceholder.swift`, `Tests/ZivletTriggerHostTests/ZivletTriggerHostSmokeTests.swift` |

### 5.1 Failing tests first

The rig drives the host only through the fake scheduler's callback, the same path the real OS layer uses. A standard
file drag is: mouse-down at 0 ms (change count 5) → first drag event at 10 ms → frame at 18 ms with count 6 and file
types → probe → taps after the 40 ms debounce mark.

`Packages/ZivletKit/Tests/ZivletTriggerHostTests/TriggerFakes.swift`:

```swift
import ZivletCore
import ZivletTrigger

@testable import ZivletTriggerHost

/// Scriptable OS reads. Tests set fields, then send a signal; the host reads them while building the sample.
final class FakeInput: InputReading {
    var uptime: Duration = .zero
    var modifiers: ModifierMask = []
    var primaryButtonDown = false
    var dragChangeCount = 0
    var location = Point2D(x: 640, y: 400)
    var pointerInsideWheel = false
    var fileTypesPresent = true
    private(set) var typeReads = 0

    func dragHasFileTypes() -> Bool {
        typeReads += 1
        return fileTypesPresent
    }
}

/// Records every plan the host applies; `send` plays the OS layer calling back into the host.
final class FakeScheduler: TriggerScheduling {
    private(set) var plans: [SamplingPlan] = []
    var onSignal: ((TriggerSignal) -> Void)?

    var current: SamplingPlan? { plans.last }
    func apply(_ plan: SamplingPlan) { plans.append(plan) }
    func send(_ signal: TriggerSignal) { onSignal?(signal) }
}

/// Change counts the payload probe was asked for.
final class ProbeLog {
    private(set) var counts: [Int] = []
    func record(_ count: Int) { counts.append(count) }
}

/// Builds a host wired to fakes and collects the wheel effects it forwards.
final class HostRig {
    let input = FakeInput()
    let scheduler = FakeScheduler()
    let probes = ProbeLog()
    private(set) var wheelEffects: [TriggerEffect] = []
    let host: TriggerHost

    var probed: [Int] { probes.counts }

    init(
        config: TriggerConfig = TriggerConfig(), flags: Bool = false,
        summary: DragSummary = DragSummary(itemCount: 1, acceptedModes: Set(WheelMode.allCases))
    ) {
        host = TriggerHost(
            config: config, reader: input, scheduler: scheduler, listensToFlagsChanged: flags,
            probe: { [probes] count in
                probes.record(count)
                return summary
            })
        host.onWheelEffect = { [unowned self] in wheelEffects.append($0) }
        host.start()
    }

    /// Advances the clock, applies OS state, then delivers one event through the scheduler callback.
    func event(
        _ source: SampleSource, at ms: Int, mods: ModifierMask? = nil, down: Bool? = nil, count: Int? = nil,
        inside: Bool? = nil
    ) {
        input.uptime = .milliseconds(ms)
        if let mods { input.modifiers = mods }
        if let down { input.primaryButtonDown = down }
        if let count { input.dragChangeCount = count }
        if let inside { input.pointerInsideWheel = inside }
        scheduler.send(.event(source))
    }

    /// Mouse-down at 0 ms (count 5), first drag event at 10 ms, file types on the pasteboard at 18 ms, probe done.
    func startFileDrag(mods: ModifierMask = []) async {
        event(.mouseDown, at: 0, mods: mods, down: true, count: 5)
        event(.mouseDragged, at: 10)
        event(.frame, at: 18, count: 6)
        await host.probeTask?.value
    }
}
```

`Packages/ZivletKit/Tests/ZivletTriggerHostTests/TriggerHostTests.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger
import Testing

@testable import ZivletTriggerHost

@Suite("Trigger host: OS signals → TriggerMachine → effects (P0-40, 03a §1.1–1.4)")
struct TriggerHostTests {
    @Test func startListensForMouseDownOnlyWithNoTimers() {
        let rig = HostRig()
        #expect(rig.scheduler.plans == [SamplingPlan(events: [.mouseDown])])
        #expect(HostRig(flags: true).scheduler.current?.events == [.mouseDown, .flagsChanged])
    }

    @Test func pressedAddsDragMonitorsAndTheWatchdog() {
        let rig = HostRig()
        rig.event(.mouseDown, at: 0, down: true, count: 5)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseDragged, .mouseUp], watchdog: true))
        rig.event(.mouseDragged, at: 10)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseUp], sampling: true))
    }

    @Test func fileDragProbesOnceAndATapShowsTheWheelAtThePointer() async {
        let rig = HostRig()
        await rig.startFileDrag()
        #expect(rig.probed == [6])
        rig.input.location = Point2D(x: 300, y: 200)
        rig.event(.frame, at: 70, mods: .shift)
        #expect(rig.wheelEffects == [.show(.convert, at: Point2D(x: 300, y: 200))])
        #expect(
            rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseUp], sampling: true, escapeHotkey: true))
    }

    @Test func fileTypesAreReadOncePerChangeCountAndNeverWhileIdle() async {
        let rig = HostRig()
        rig.event(.frame, at: 0, count: 9)
        #expect(rig.input.typeReads == 0)
        await rig.startFileDrag()
        rig.event(.frame, at: 30)
        rig.event(.frame, at: 40)
        #expect(rig.input.typeReads == 1)
    }

    @Test func nonFileDragGoesPassiveWithOnlyTheWatchdog() {
        let rig = HostRig()
        rig.input.fileTypesPresent = false
        rig.event(.mouseDown, at: 0, down: true, count: 5)
        rig.event(.mouseDragged, at: 10)
        rig.event(.frame, at: 18, count: 6)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseUp], watchdog: true))
        rig.event(.frame, at: 500, down: false)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown]))
        #expect(rig.probed.isEmpty && rig.wheelEffects.isEmpty)
    }

    @Test func eventSourceDecidesTheButtonForMouseEvents() {
        let rig = HostRig()
        rig.event(.mouseDown, at: 0, down: false, count: 1)
        #expect(rig.host.machine.state == .pressed(snapshot: 1, held: []))
        rig.event(.mouseUp, at: 5, down: true)
        #expect(rig.host.machine.state == .idle)
    }

    @Test func heldModifierIsIgnoredUntilPressedAgain() async {
        let rig = HostRig()
        await rig.startFileDrag(mods: .command)
        rig.event(.frame, at: 70)
        #expect(rig.wheelEffects.isEmpty)
        rig.event(.frame, at: 80, mods: [])
        rig.event(.frame, at: 90, mods: .command)
        #expect(rig.wheelEffects == [.show(.tools, at: rig.input.location)])
    }

    @Test func releaseOutsideHidesAndReturnsToIdle() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .control)
        rig.event(.mouseUp, at: 90, down: false, inside: false)
        #expect(rig.wheelEffects.last == .hide(.buttonUp))
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown]))
    }

    @Test func dropInsideWaitsForDropHandled() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.event(.mouseUp, at: 90, down: false, inside: true)
        #expect(rig.wheelEffects.count == 1)
        rig.scheduler.send(.dropHandled)
        #expect(rig.wheelEffects.last == .hide(.dropped))
        #expect(rig.host.machine.state == .idle)
    }

    @Test func escapeAndSpaceChangeHideTheWheel() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.scheduler.send(.escape)
        #expect(rig.wheelEffects.last == .hide(.escape))
        rig.event(.frame, at: 80, mods: [])
        rig.event(.frame, at: 90, mods: .shift)
        rig.scheduler.send(.spaceChanged)
        #expect(rig.wheelEffects.last == .hide(.spaceChanged))
    }

    @Test func switchAndRejectAreForwarded() async {
        let rig = HostRig(summary: DragSummary(itemCount: 1, acceptedModes: [.convert, .actions]))
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.event(.frame, at: 80, mods: .control)
        rig.event(.frame, at: 90, mods: .command)
        #expect(rig.wheelEffects.dropFirst() == [.switchTo(.actions), .reject(.tools, .noItemsForMode)])
    }

    @Test func aLateProbeAfterTheDragEndedChangesNothing() async {
        let rig = HostRig()
        rig.event(.mouseDown, at: 0, down: true, count: 5)
        rig.event(.mouseDragged, at: 10)
        rig.event(.frame, at: 18, count: 6)
        rig.event(.mouseUp, at: 20, down: false)
        await rig.host.probeTask?.value
        #expect(rig.host.machine.state == .idle && rig.wheelEffects.isEmpty)
    }

    @Test func newBindingsApplyFromTheNextEdge() async throws {
        let rig = HostRig()
        let swapped = try TriggerBindings(convert: .option, tools: .command, actions: .control)
        rig.host.update(config: TriggerConfig(bindings: swapped))
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .option)
        #expect(rig.wheelEffects == [.show(.convert, at: rig.input.location)])
    }

    @Test func stopTurnsEverythingOff() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.host.stop()
        #expect(rig.scheduler.current == SamplingPlan(events: []))
        #expect(rig.host.machine.state == .idle)
    }

    @Test func appKitFlagsMapToTheFourTriggerModifiers() {
        let flags: NSEvent.ModifierFlags = [.shift, .command, .capsLock, .function, .numericPad]
        #expect(ModifierMask(flags) == [.shift, .command])
        #expect(ModifierMask(NSEvent.ModifierFlags([.control, .option])) == [.control, .option])
        #expect(ModifierMask(NSEvent.ModifierFlags()) == [])
    }
}
```

### 5.2 Run, expect failure

`swift test --filter ZivletTriggerHostTests` → `error: cannot find type 'InputReading' in scope` (also
`SamplingPlan`, `TriggerScheduling`, `TriggerSignal`, `TriggerHost`).

### 5.3 Implement (complete)

`Packages/ZivletKit/Sources/ZivletTriggerHost/TriggerPorts.swift`:

```swift
import ZivletCore
import ZivletTrigger

/// OS events the host can ask to be woken by (03a §1.3).
public enum MonitoredEvent: String, Sendable, Hashable, CaseIterable {
    case mouseDown, mouseDragged, mouseUp, flagsChanged

    public var source: SampleSource {
        switch self {
        case .mouseDown: .mouseDown
        case .mouseDragged: .mouseDragged
        case .mouseUp: .mouseUp
        case .flagsChanged: .flagsChanged
        }
    }
}

/// Everything the OS layer should be doing right now. The host recomputes it after each step and applies it only
/// when it changes, so the OS layer never sees duplicate requests.
public struct SamplingPlan: Sendable, Equatable {
    public let events: Set<MonitoredEvent>
    /// Display-rate sampler: only while a drag is detected, live or showing the wheel.
    public let sampling: Bool
    /// 2 Hz button watchdog: only in `pressed` and `passive` (03a §1.5).
    public let watchdog: Bool
    /// Esc hotkey: only while the wheel is visible (03a §1.8).
    public let escapeHotkey: Bool

    public init(
        events: Set<MonitoredEvent>, sampling: Bool = false, watchdog: Bool = false, escapeHotkey: Bool = false
    ) {
        self.events = events
        self.sampling = sampling
        self.watchdog = watchdog
        self.escapeHotkey = escapeHotkey
    }

    public static let off = SamplingPlan(events: [])
}

/// What the OS layer reports back to the host.
public enum TriggerSignal: Sendable, Equatable {
    case event(SampleSource)
    case escape
    case spaceChanged
    case dropHandled
}

/// Every OS read the host makes, behind one protocol so the host logic runs against a fake in tests.
public protocol InputReading: AnyObject {
    var uptime: Duration { get }
    var modifiers: ModifierMask { get }
    var primaryButtonDown: Bool { get }
    var dragChangeCount: Int { get }
    var location: Point2D { get }
    var pointerInsideWheel: Bool { get }
    /// Types only: file URLs or file promises on the drag pasteboard. Never reads URLs or data (14 §1.3).
    func dragHasFileTypes() -> Bool
}

/// Monitors, sampler, watchdog and hotkey. Calls `onSignal` on the main actor.
public protocol TriggerScheduling: AnyObject {
    var onSignal: ((TriggerSignal) -> Void)? { get set }
    func apply(_ plan: SamplingPlan)
}
```

The probe result is fed back as `.payload`; the machine ignores a payload for a stale change count or after the drag
ended, so a late probe changes nothing (test `aLateProbeAfterTheDragEndedChangesNothing`).

`Packages/ZivletKit/Sources/ZivletTriggerHost/TriggerHost.swift`:

```swift
import ZivletCore
import ZivletTrigger

/// The AppKit-side driver of the pure `TriggerMachine` (03a §1.1): turns OS signals into `InputSample`s, steps the
/// machine and executes its effects. Monitor, sampler and timer effects become a `SamplingPlan`; wheel effects go
/// to `onWheelEffect`; `probePayload` runs the injected probe and feeds the result back as `.payload`.
public final class TriggerHost {
    public typealias PayloadProbe = @MainActor (Int) async -> DragSummary

    public private(set) var machine: TriggerMachine
    public private(set) var plan = SamplingPlan.off
    /// The running payload probe; tests await it.
    public private(set) var probeTask: Task<Void, Never>?
    public var onWheelEffect: (TriggerEffect) -> Void = { _ in }

    private let reader: any InputReading
    private let scheduler: any TriggerScheduling
    private let probe: PayloadProbe
    private let baseEvents: Set<MonitoredEvent>
    private var dragEvents: Set<MonitoredEvent> = []
    private var sampling = false
    private var fileTypes: (changeCount: Int, present: Bool)?

    public init(
        config: TriggerConfig = TriggerConfig(), reader: any InputReading, scheduler: any TriggerScheduling,
        listensToFlagsChanged: Bool = false, probe: @escaping PayloadProbe
    ) {
        machine = TriggerMachine(config: config)
        self.reader = reader
        self.scheduler = scheduler
        self.probe = probe
        baseEvents = listensToFlagsChanged ? [.mouseDown, .flagsChanged] : [.mouseDown]
        scheduler.onSignal = { [weak self] in self?.receive($0) }
    }

    /// Idle: only the mouse-down monitors, no timers (03a §1.5: zero idle wakeups).
    public func start() { applyPlanIfChanged() }

    public func stop() {
        probeTask?.cancel()
        machine = TriggerMachine(config: machine.config)
        dragEvents = []
        sampling = false
        plan = .off
        scheduler.apply(.off)
    }

    /// T19: new bindings apply from the next edge.
    public func update(config: TriggerConfig) { machine = machine.with(config: config) }

    public func receive(_ signal: TriggerSignal) {
        switch signal {
        case .event(let source): step(.sample(sample(source)))
        case .escape: step(.escape)
        case .spaceChanged: step(.spaceChanged)
        case .dropHandled: step(.dropHandled)
        }
    }

    private func step(_ event: TriggerEvent) {
        let result = machine.step(event)
        machine = result.next
        result.effects.forEach(execute)
        applyPlanIfChanged()
    }

    private func execute(_ effect: TriggerEffect) {
        switch effect {
        case .installDragMonitors: dragEvents = [.mouseDragged, .mouseUp]
        case .removeDraggedMonitor: dragEvents.remove(.mouseDragged)
        case .removeDragMonitors: dragEvents = []
        case .startSampler: sampling = true
        case .stopSampler: sampling = false
        case .probePayload(let count): startProbe(count)
        case .show, .switchTo, .reject, .hide: onWheelEffect(effect)
        }
    }

    private func startProbe(_ count: Int) {
        probeTask?.cancel()
        probeTask = Task { [weak self, probe] in
            let summary = await probe(count)
            guard !Task.isCancelled else { return }
            self?.step(.payload(changeCount: count, summary: summary))
        }
    }

    private func sample(_ source: SampleSource) -> InputSample {
        let count = reader.dragChangeCount
        return InputSample(
            uptime: reader.uptime, source: source, modifiers: reader.modifiers,
            primaryButtonDown: buttonDown(for: source), dragChangeCount: count,
            dragHasFileTypes: hasFileTypes(count), location: reader.location,
            pointerInsideWheel: reader.pointerInsideWheel)
    }

    /// A mouse event states the button itself; `pressedMouseButtons` can lag behind a quick click.
    private func buttonDown(for source: SampleSource) -> Bool {
        switch source {
        case .mouseDown, .mouseDragged: true
        case .mouseUp: false
        case .frame, .flagsChanged: reader.primaryButtonDown
        }
    }

    /// Types-only check, only while detecting and once per change count (03a §1.2).
    private func hasFileTypes(_ count: Int) -> Bool {
        guard case .detecting(let snapshot, _, _) = machine.state, count != snapshot else { return false }
        if let cached = fileTypes, cached.changeCount == count { return cached.present }
        let present = reader.dragHasFileTypes()
        fileTypes = (count, present)
        return present
    }

    private func applyPlanIfChanged() {
        let next = SamplingPlan(
            events: baseEvents.union(dragEvents), sampling: sampling, watchdog: needsWatchdog,
            escapeHotkey: wheelVisible)
        guard next != plan else { return }
        plan = next
        scheduler.apply(next)
    }

    private var needsWatchdog: Bool {
        switch machine.state {
        case .pressed, .passive: true
        default: false
        }
    }

    private var wheelVisible: Bool {
        switch machine.state {
        case .wheel, .releasing: true
        default: false
        }
    }
}
```

`Packages/ZivletKit/Sources/ZivletTriggerHost/ModifierMask+AppKit.swift`:

```swift
import AppKit
import ZivletTrigger

extension ModifierMask {
    /// Keeps ⌃⌥⇧⌘ only; Caps Lock, Fn and numeric-pad bits are dropped (03a §1.2).
    public init(_ flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, ModifierMask)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        let raw = pairs.reduce(UInt8(0)) { bits, pair in flags.contains(pair.0) ? bits | pair.1.rawValue : bits }
        self.init(rawValue: raw)
    }
}
```

Delete the placeholder and the smoke test:

```bash
git rm -q Sources/ZivletTriggerHost/ZivletTriggerHostPlaceholder.swift \
          Tests/ZivletTriggerHostTests/ZivletTriggerHostSmokeTests.swift
```

### 5.4 Verify green

`swift test --filter ZivletTriggerHostTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 15 tests in 1 suite passed`.

### 5.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletTriggerHost Packages/ZivletKit/Tests/ZivletTriggerHostTests
git commit -s -m "feat(trigger): add TriggerHost driving TriggerMachine through OS ports"
```

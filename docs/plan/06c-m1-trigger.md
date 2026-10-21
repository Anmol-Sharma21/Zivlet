# 06c — M1 task 6: TriggerMachine

Part of [06-implementation-plan-m1](06-implementation-plan-m1.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 6 — Modifier bindings and the pure TriggerMachine

| Field | Value |
|---|---|
| Goal | A clock-free, AppKit-free state machine: file-drag detection by drag-pasteboard `changeCount` + file types, press-edge exact-match wheel opening, mode switch, re-tap close, Esc, release handling; plus validated bindings |
| 05 rows | P0-21, P0-23 (JSON traces of P0-22 follow later; this task uses an in-code trace DSL) |
| Sources | 03a §1.1–1.7 (split, inputs, states, transitions T1–T19, numbers, bindings), 02 §7.6 (contract), 14 §1.3 |

Numbers (03a §1.5), all in `TriggerConfig` so the host and tests can change them:

| Parameter | Default | Note |
|---|---|---|
| `detectionWindow` | 300 ms after the first drag event | then `passive` |
| `edgeDebounce` | 40 ms after entering `live` | earlier edges are held and fire at the mark with the then-current modifiers |
| `releaseTimeout` | **150 ms** | Zivlet's spec, configurable (index D3); a test also runs 300 ms |
| `honorsModifierHeldAtDragStart` | `false` | [critic3] a key held before the drag is ignored until released and pressed again (01-prd FR-4, D-3; index D4). `true` = a held key opens the wheel, tested |
| `retapClosesWheel` | `true` | Zivlet addition (D-2) |

Two TDD cycles, two commits.

### 6a — Modifier masks and bindings

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletCore/Shared/WheelMode.swift`, `Sources/ZivletCore/Shared/Point2D.swift` (index D2) |
| create | `Sources/ZivletTrigger/ModifierMask.swift` — `ModifierMask`, `BindingError`, `TriggerBindings` |
| create | `Tests/ZivletTriggerTests/TriggerBindingsTests.swift` |
| delete | `Sources/ZivletTrigger/ZivletTriggerPlaceholder.swift`, `Tests/ZivletTriggerTests/ZivletTriggerSmokeTests.swift` |

#### 6a.1 Failing tests first

```swift
import ZivletCore
import Testing

@testable import ZivletTrigger

@Suite("Modifier masks and bindings (P0-21, 03a §1.7)")
struct TriggerBindingsTests {
    @Test func defaultsAreShiftCommandControl() {
        let b = TriggerBindings.standard
        #expect(b.mode(matching: .shift) == .convert)
        #expect(b.mode(matching: .command) == .tools)
        #expect(b.mode(matching: .control) == .actions)
        #expect(b.menuSummary == "⇧: Convert · ⌘: Tools · ⌃: Actions")
    }

    @Test func matchIsExact() {
        let b = TriggerBindings.standard
        #expect(b.mode(matching: [.shift, .command]) == nil)
        #expect(b.mode(matching: []) == nil)
        #expect(b.mode(matching: .option) == nil)
    }

    @Test func fifteenNonEmptyCombos() {
        #expect(ModifierMask.allNonEmpty.count == 15)
        #expect(Set(ModifierMask.allNonEmpty).count == 15)
        #expect(ModifierMask(rawValue: 0xFF) == [.control, .option, .shift, .command])
        #expect(ModifierMask([.command, .control, .shift]).symbols == "⌃⇧⌘")
    }

    @Test func emptyAndDuplicateBindingsAreRejected() {
        #expect(throws: BindingError.emptyMask(.tools)) {
            try TriggerBindings(convert: .shift, tools: [], actions: .control)
        }
        #expect(throws: BindingError.duplicate(.shift)) {
            try TriggerBindings(convert: .shift, tools: .shift, actions: .control)
        }
        #expect(throws: BindingError.duplicate(.option)) {
            try TriggerBindings(convert: .shift, tools: .option, actions: .option)
        }
    }

    @Test func chordBindingsWork() throws {
        let b = try TriggerBindings(convert: [.option, .shift], tools: .command, actions: .control)
        #expect(b.mode(matching: [.option, .shift]) == .convert)
        #expect(b.mode(matching: .shift) == nil)
    }
}
```

#### 6a.2 Run, expect failure

`swift test --filter ZivletTriggerTests` → `error: cannot find 'TriggerBindings' in scope` (and `ModifierMask`,
`WheelMode`).

#### 6a.3 Implement

Core additions (complete):

```swift
/// The three wheels. Lives in Core because both Trigger and WheelCore need it (02 §4 graph).
public enum WheelMode: String, CaseIterable, Codable, Sendable {
    case convert, tools, actions
}
```

```swift
/// Plain point in points, AppKit orientation (y up). Keeps pure modules free of CoreGraphics.
public struct Point2D: Sendable, Hashable, Codable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public static let zero = Point2D(x: 0, y: 0)
}
```

`ModifierMask.swift` — outline:

```swift
public struct ModifierMask: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue & 0b1111 }   // ⌃⌥⇧⌘ only
    public static let control = ModifierMask(rawValue: 1 << 0), option = …(1 << 1), shift = …(1 << 2), command = …(1 << 3)
    public static let allNonEmpty: [ModifierMask]                        // raw values 1…15
    public var symbols: String                                          // "⌃⌥⇧⌘" order
}

public enum BindingError: Error, Equatable, Sendable { case emptyMask(WheelMode), duplicate(ModifierMask) }

public struct TriggerBindings: Sendable, Equatable, Codable {
    public static let schemaVersion = 1
    public static let standard: TriggerBindings                          // ⇧ convert, ⌘ tools, ⌃ actions (private unchecked init)
    public let convert: ModifierMask, tools: ModifierMask, actions: ModifierMask
    public init(convert: ModifierMask, tools: ModifierMask, actions: ModifierMask) throws(BindingError)
    public func mode(matching mask: ModifierMask) -> WheelMode?          // EXACT equality; checks tools → convert → actions
    public var menuSummary: String                                       // "⇧: Convert · ⌘: Tools · ⌃: Actions"
}
```

Validation order in `init`: first empty mask (in convert, tools, actions order) → `emptyMask`; then `convert` equal to
`tools` or `actions` → `duplicate(convert)`; then `tools == actions` → `duplicate(tools)`.

[review] `TriggerBindings` has a hand-written `Codable`: it encodes `{schemaVersion, convert, tools, actions}` and
`init(from:)` requires `schemaVersion == 1`, then calls the validating `init`, mapping `BindingError` to
`DecodingError.dataCorrupted`. A synthesized decoder would have accepted empty or duplicate masks from a stored file.
Tests: `encodingCarriesTheSchemaVersionAndRoundTrips`, `invalidPayloadsFailToDecode` (empty, duplicate, wrong or
missing version).

#### 6a.4 Verify green and commit

`swift test --filter ZivletTriggerTests` → `✔ Test run with 5 tests in 1 suite passed`.

```bash
git add -A Packages/ZivletKit
git commit -s -m "feat(trigger): add modifier masks and validated wheel bindings"
```

### 6b — TriggerMachine

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletTrigger/TriggerTypes.swift` — samples, events, effects, config |
| create | `Sources/ZivletTrigger/TriggerState.swift` — states with immutable payloads |
| create | `Sources/ZivletTrigger/TriggerMachine.swift` — dispatch + T1–T5 |
| create | `Sources/ZivletTrigger/TriggerMachine+Live.swift` — T3, T6–T9 |
| create | `Sources/ZivletTrigger/TriggerMachine+Wheel.swift` — T10–T18 |
| create | `Tests/ZivletTriggerTests/TriggerScript.swift` — trace DSL (`T.fileDrag`, `T.tap`, `T.run`) |
| create | `Tests/ZivletTriggerTests/TriggerMachineTests.swift` |
| create | `Tests/ZivletTriggerTests/TriggerPropertyTests.swift` — 2 × 200 seeded random traces |

#### 6b.1 Failing tests first

The DSL folds events through the machine with `reduce`, so tests never mutate shared state. A standard file drag is:
mouse-down at 0 ms (change count 0) → first drag event at 10 ms → frame at 18 ms where the count is 1 and file types
are present (→ `live`) → payload. Taps start after the 40 ms debounce mark (58 ms).

```swift
import ZivletCore

@testable import ZivletTrigger

/// Test DSL: builds events and folds them through the machine without mutation of shared state.
enum T {
    static let here = Point2D(x: 100, y: 200)
    static let everyMode = DragSummary(itemCount: 1, acceptedModes: Set(WheelMode.allCases))

    static func sample(
        _ ms: Int, _ source: SampleSource = .frame, mods: ModifierMask = [], down: Bool = true,
        cc: Int = 1, files: Bool = true, inside: Bool = false
    ) -> TriggerEvent {
        .sample(
            InputSample(
                uptime: .milliseconds(ms), source: source, modifiers: mods, primaryButtonDown: down,
                dragChangeCount: cc, dragHasFileTypes: files, location: here, pointerInsideWheel: inside))
    }

    /// mouse-down (cc 0) → first drag event → frame where the count moved with file types → payload.
    static func fileDrag(held: ModifierMask = [], summary: DragSummary = everyMode) -> [TriggerEvent] {
        [
            sample(0, .mouseDown, mods: held, cc: 0, files: false),
            sample(10, .mouseDragged, mods: held, cc: 0, files: false),
            sample(18, mods: held, cc: 1),
            .payload(changeCount: 1, summary: summary),
        ]
    }

    /// A tap: key down then key up, both after the 40 ms debounce (drag went live at 18 ms).
    static func tap(_ mods: ModifierMask, at ms: Int) -> [TriggerEvent] {
        [sample(ms, .flagsChanged, mods: mods), sample(ms + 30, .flagsChanged)]
    }

    struct Run {
        let machine: TriggerMachine
        let effects: [TriggerEffect]
    }

    static func run(_ events: [TriggerEvent], config: TriggerConfig = TriggerConfig()) -> Run {
        events.reduce(Run(machine: TriggerMachine(config: config), effects: [])) { acc, event in
            let step = acc.machine.step(event)
            return Run(machine: step.next, effects: acc.effects + step.effects)
        }
    }
}
```

```swift
import ZivletCore
import Testing

@testable import ZivletTrigger

@Suite("TriggerMachine (P0-23, 03a §1.4)")
struct TriggerMachineTests {
    @Test func fileDragThenShiftTapShowsConvertWheelAtPointer() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100))
        #expect(
            run.effects == [
                .installDragMonitors, .removeDraggedMonitor, .startSampler,
                .probePayload(changeCount: 1), .show(.convert, at: T.here),
            ])
        #expect(run.machine.state.isWheel(.convert))
    }

    @Test func keyReleaseNeverChangesTheWheel() {
        let run = T.run(T.fileDrag() + [T.sample(100, mods: .shift), T.sample(130), T.sample(160)])
        #expect(run.effects.filter { $0.isWheelChange } == [.show(.convert, at: T.here)])
    }

    @Test func nonFileDragGoesPassiveAndNeverShows() {
        let events =
            [
                T.sample(0, .mouseDown, cc: 0, files: false), T.sample(10, .mouseDragged, cc: 0, files: false),
                T.sample(18, cc: 1, files: false),
            ] + T.tap(.shift, at: 100)
        let run = T.run(events)
        #expect(run.machine.state == .passive)
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test func detectionWindowExpiresAfter300ms() {
        let events = [
            T.sample(0, .mouseDown, cc: 0), T.sample(10, .mouseDragged, cc: 0),
            T.sample(309, cc: 0), T.sample(310, cc: 0),
        ]
        let run = T.run(events)
        #expect(run.machine.state == .passive)
        #expect(run.effects.last == .stopSampler)
    }

    @Test func unboundChordIsIgnored() {
        let run = T.run(T.fileDrag() + T.tap([.shift, .command], at: 100))
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test func modifierHeldBeforeDragIsIgnoredByDefault() {
        let run = T.run(T.fileDrag(held: .command) + [T.sample(60, mods: .command)])
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test func heldModifierOpensWheelOnceReleasedAndPressedAgain() {
        let run = T.run(T.fileDrag(held: .command) + [T.sample(60), T.sample(70, mods: .command)])
        #expect(run.effects.last == .show(.tools, at: T.here))
    }

    @Test func modifierHeldBeforeDragOpensWheelWhenParityIsOn() {
        let config = TriggerConfig(honorsModifierHeldAtDragStart: true)
        let run = T.run(T.fileDrag(held: .command) + [T.sample(60, mods: .command)], config: config)
        #expect(run.effects.last == .show(.tools, at: T.here))
    }

    @Test func edgeBeforePayloadIsQueuedAndAppliedOnArrival() {
        let drag = Array(T.fileDrag().dropLast())  // payload not yet delivered
        let run = T.run(drag + [T.sample(70, mods: .control), .payload(changeCount: 1, summary: T.everyMode)])
        #expect(run.effects.last == .show(.actions, at: T.here))
    }

    @Test func edgeInsideDebounceFiresAtTheMarkWithCurrentSet() {
        let early = T.run(T.fileDrag() + [T.sample(25, mods: .shift)])  // 7 ms after live
        #expect(!early.effects.contains { $0.isShow })
        let atMark = T.run(T.fileDrag() + [T.sample(25, mods: .shift), T.sample(58, mods: [.shift, .command])])
        #expect(!atMark.effects.contains { $0.isShow }, "⇧⌘ at the mark is unbound")
        let resolved = T.run(T.fileDrag() + [T.sample(25, mods: .shift), T.sample(58, mods: .shift)])
        #expect(resolved.effects.last == .show(.convert, at: T.here))
    }

    @Test func otherBindingSwitchesInPlace() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + T.tap(.command, at: 200))
        #expect(run.effects.suffix(2) == [.show(.convert, at: T.here), .switchTo(.tools)])
        #expect(run.machine.state.isWheel(.tools))
    }

    @Test func switchToWheelThatRejectsItemsKeepsOldWheel() {
        let summary = DragSummary(itemCount: 1, acceptedModes: [.convert, .actions])
        let run = T.run(T.fileDrag(summary: summary) + T.tap(.shift, at: 100) + T.tap(.command, at: 200))
        #expect(run.effects.last == .reject(.tools, .noItemsForMode))
        #expect(run.machine.state.isWheel(.convert))
    }

    @Test func retapClosesAndAThirdTapReopens() {
        let closed = T.run(T.fileDrag() + T.tap(.shift, at: 100) + T.tap(.shift, at: 200))
        #expect(closed.effects.last == .hide(.sameModifierRetap))
        let reopened = T.run(T.fileDrag() + T.tap(.shift, at: 100) + T.tap(.shift, at: 200) + T.tap(.shift, at: 300))
        #expect(reopened.effects.last == .show(.convert, at: T.here))
    }

    @Test func releaseOutsideWheelHidesAtOnce() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [T.sample(400, .mouseUp, down: false)])
        #expect(run.effects.suffix(3) == [.hide(.buttonUp), .stopSampler, .removeDragMonitors])
        #expect(run.machine.state == .idle)
    }

    @Test func releaseInsideWaitsForDropHandled() {
        let events =
            T.fileDrag() + T.tap(.shift, at: 100) + [
                T.sample(400, .mouseUp, down: false, inside: true),
                T.sample(450, down: false, inside: true), .dropHandled,
            ]
        let run = T.run(events)
        #expect(run.effects.suffix(3) == [.hide(.dropped), .stopSampler, .removeDragMonitors])
    }

    @Test(arguments: [(150, 549, 550), (300, 699, 700)])
    func releaseInsideTimesOut(timeoutMs: Int, before: Int, at: Int) {
        let config = TriggerConfig(releaseTimeout: .milliseconds(timeoutMs))
        let base = T.fileDrag() + T.tap(.shift, at: 100) + [T.sample(400, .mouseUp, down: false, inside: true)]
        let waiting = T.run(base + [T.sample(before, down: false)], config: config)
        #expect(waiting.machine.state == .releasing(mode: .convert, deadline: .milliseconds(400 + timeoutMs)))
        let expired = T.run(base + [T.sample(at, down: false)], config: config)
        #expect(expired.effects.suffix(3) == [.hide(.lingerExpired), .stopSampler, .removeDragMonitors])
    }

    @Test func escapeHidesButKeepsTheDragLive() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [.escape])
        #expect(run.effects.last == .hide(.escape))
        #expect(run.machine.state.isLive)
        let again = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [.escape] + T.tap(.command, at: 300))
        #expect(again.effects.last == .show(.tools, at: T.here))
    }

    @Test func escapeWhileReleasingGoesIdle() {
        let events =
            T.fileDrag() + T.tap(.shift, at: 100) + [T.sample(400, .mouseUp, down: false, inside: true), .escape]
        #expect(T.run(events).effects.suffix(3) == [.hide(.escape), .stopSampler, .removeDragMonitors])
    }

    @Test func spaceChangeHides() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [.spaceChanged])
        #expect(run.effects.last == .hide(.spaceChanged))
    }

    @Test(arguments: [1, 2, 3])
    func buttonUpBeforeWheelReturnsToIdle(prefixLength: Int) {
        let events = Array(T.fileDrag().prefix(prefixLength)) + [T.sample(50, .mouseUp, down: false)]
        let run = T.run(events)
        #expect(run.machine.state == .idle)
        #expect(run.effects.suffix(2) == [.stopSampler, .removeDragMonitors])
    }

    @Test func staleOrUnexpectedEventsAreNoOps() {
        let idle = TriggerMachine()
        #expect(idle.step(.escape) == TriggerStep(next: idle, effects: []))
        #expect(idle.step(T.sample(5)) == TriggerStep(next: idle, effects: []))
        let live = T.run(Array(T.fileDrag().dropLast())).machine
        #expect(live.step(.payload(changeCount: 99, summary: T.everyMode)).next == live)
    }

    @Test func newBindingsApplyFromTheNextEdge() throws {
        let config = TriggerConfig(bindings: try TriggerBindings(convert: .option, tools: .command, actions: .control))
        let live = T.run(T.fileDrag()).machine.with(config: config)
        #expect(live.state.isLive)
        #expect(live.step(T.sample(100, mods: .option)).effects == [.show(.convert, at: T.here)])
    }
}

extension TriggerState {
    func isWheel(_ mode: WheelMode) -> Bool {
        if case .wheel(let w) = self { return w.mode == mode }
        return false
    }
    var isLive: Bool {
        if case .live = self { return true }
        return false
    }
}

extension TriggerEffect {
    var isShow: Bool {
        if case .show = self { return true }
        return false
    }
    var isWheelChange: Bool {
        switch self {
        case .show, .switchTo, .hide: true
        default: false
        }
    }
}
```

```swift
import ZivletCore
import TestSupport
import Testing

@testable import ZivletTrigger

@Suite("TriggerMachine properties")
struct TriggerPropertyTests {
    static func randomEvents(seed: UInt64, count: Int, files: Bool) -> [TriggerEvent] {
        var rng = SplitMix64(seed: seed)
        let sources: [SampleSource] = [.mouseDown, .mouseDragged, .mouseUp, .frame, .flagsChanged]
        return (0..<count).map { i in
            if Int.random(in: 0..<10, using: &rng) == 0 {
                return [.escape, .spaceChanged, .dropHandled].randomElement(using: &rng)!
            }
            return T.sample(
                i * 9, sources.randomElement(using: &rng)!,
                mods: ModifierMask(rawValue: UInt8.random(in: 0...15, using: &rng)),
                down: Bool.random(using: &rng), cc: Int.random(in: 0...3, using: &rng), files: files)
        }
    }

    @Test(arguments: 0..<200)
    func neverShowsWithoutAFileDrag(seed: Int) {
        let run = T.run(Self.randomEvents(seed: UInt64(seed), count: 120, files: false))
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test(arguments: 0..<200)
    func everyShowIsPairedWithAtMostOneOpenWheel(seed: Int) {
        let run = T.run(
            Self.randomEvents(seed: UInt64(seed), count: 120, files: true)
                + [.payload(changeCount: 1, summary: T.everyMode)])
        var open = false
        for effect in run.effects {
            switch effect {
            case .show:
                #expect(!open)
                open = true
            case .hide:
                #expect(open)
                open = false
            case .switchTo, .reject: #expect(open)
            default: break
            }
        }
    }
}
```

#### 6b.2 Run, expect failure

`swift test --filter ZivletTriggerTests` → `error: cannot find type 'TriggerEvent' in scope` (and `TriggerMachine`,
`InputSample`, `DragSummary`, `TriggerConfig`).

#### 6b.3 Implement

`TriggerTypes.swift` — outline (names are exactly what the tests use):

```swift
public enum SampleSource: String, Sendable, Codable { case mouseDown, mouseDragged, mouseUp, frame, flagsChanged }

public struct InputSample: Sendable, Equatable, Codable {          // all let; init has defaults for the last five
    public let uptime: Duration, source: SampleSource, modifiers: ModifierMask, primaryButtonDown: Bool
    public let dragChangeCount: Int, dragHasFileTypes: Bool, location: Point2D, pointerInsideWheel: Bool
    public init(uptime: Duration, source: SampleSource, modifiers: ModifierMask = [], primaryButtonDown: Bool,
                dragChangeCount: Int, dragHasFileTypes: Bool = false, location: Point2D = .zero,
                pointerInsideWheel: Bool = false)
}
public struct DragSummary: Sendable, Equatable, Codable {          // built by the host probe once per change count
    public let itemCount: Int, acceptedModes: Set<WheelMode>
    public init(itemCount: Int, acceptedModes: Set<WheelMode>)
}
public enum TriggerEvent: Sendable, Equatable {
    case sample(InputSample), payload(changeCount: Int, summary: DragSummary), escape, spaceChanged, dropHandled
}
public enum HideReason: String, Sendable, Codable { case sameModifierRetap, escape, buttonUp, lingerExpired, spaceChanged, dropped }
public enum RejectReason: String, Sendable, Codable { case noItemsForMode }
public enum TriggerEffect: Sendable, Equatable {                   // host effects are idempotent
    case installDragMonitors, removeDraggedMonitor, removeDragMonitors, startSampler, stopSampler
    case probePayload(changeCount: Int), show(WheelMode, at: Point2D), switchTo(WheelMode)
    case reject(WheelMode, RejectReason), hide(HideReason)
}
public struct TriggerConfig: Sendable, Equatable {                 // all let; init defaults = the numbers table above
    public init(bindings: TriggerBindings = .standard, honorsModifierHeldAtDragStart: Bool = false,
                retapClosesWheel: Bool = true, detectionWindow: Duration = .milliseconds(300),
                edgeDebounce: Duration = .milliseconds(40), releaseTimeout: Duration = .milliseconds(150))
}
```

`TriggerState.swift` (complete; payloads are `let`, changes go through the copy helpers):

```swift
import ZivletCore

/// 03a §1.3. Associated values are immutable; every step builds new values.
public enum TriggerState: Sendable, Equatable {
    case idle
    case pressed(snapshot: Int, held: ModifierMask)
    case detecting(snapshot: Int, held: ModifierMask, deadline: Duration)
    case passive
    case live(Live)
    case wheel(Wheel)
    case releasing(mode: WheelMode, deadline: Duration)

    /// File drag detected, no wheel. `summary` is nil while the payload probe runs.
    public struct Live: Sendable, Equatable {
        public let changeCount: Int
        public let summary: DragSummary?
        public let previous: ModifierMask
        public let liveStart: Duration
        public let pendingEdge: Bool
        public let queued: WheelMode?
        public let location: Point2D

        func observing(_ s: InputSample, pendingEdge: Bool) -> Live {
            Live(
                changeCount: changeCount, summary: summary, previous: s.modifiers, liveStart: liveStart,
                pendingEdge: pendingEdge, queued: queued, location: s.location)
        }

        func queueing(_ mode: WheelMode) -> Live {
            Live(
                changeCount: changeCount, summary: summary, previous: previous, liveStart: liveStart,
                pendingEdge: pendingEdge, queued: mode, location: location)
        }

        func receiving(_ summary: DragSummary) -> Live {
            Live(
                changeCount: changeCount, summary: summary, previous: previous, liveStart: liveStart,
                pendingEdge: pendingEdge, queued: nil, location: location)
        }
    }

    /// Wheel visible; `anchor` never follows the pointer.
    public struct Wheel: Sendable, Equatable {
        public let mode: WheelMode
        public let changeCount: Int
        public let summary: DragSummary
        public let previous: ModifierMask
        public let anchor: Point2D

        func with(mode: WheelMode? = nil, previous: ModifierMask) -> Wheel {
            Wheel(
                mode: mode ?? self.mode, changeCount: changeCount, summary: summary, previous: previous,
                anchor: anchor)
        }
    }
}

public struct TriggerStep: Sendable, Equatable {
    public let next: TriggerMachine
    public let effects: [TriggerEffect]
}
```

Transition map (03a §1.4 → code):

| 03a row | Code path | Effects |
|---|---|---|
| T1 | `idle` + `mouseDown` sample | `installDragMonitors` |
| T2 | `pressed` + `mouseDragged` | `removeDraggedMonitor`, `startSampler`; deadline = t + 300 ms |
| T3 | button up in `pressed`/`detecting`/`passive`/`live` | `toIdle()` = `stopSampler`, `removeDragMonitors` |
| T4 | `detecting`, count ≠ snapshot, file types | → `live`, `probePayload(cc)`; count moved without file types → `passive` (03a §1.3 meaning of passive) |
| T5 | `detecting`, t ≥ deadline | → `passive`, `stopSampler` |
| T6/T7 | match before the payload → `queued`; payload arrives → show | `show(mode, at:)` |
| T8/T9 | edge ∧ exact match ∧ debounce passed | `show(mode, at: location)`; a non-accepting wheel still shows (empty pill, refuses drops) |
| T10 | same binding again | `hide(.sameModifierRetap)` → `live` (debounce not re-applied) |
| T11/T12 | other binding: accepted → `switchTo`; not accepted → `reject`, old wheel stays | — |
| T13 | unbound chord (⇧⌘) | none |
| T14/T15 | button up outside → `hide(.buttonUp)` + idle; inside → `releasing(deadline = t + 150 ms)` | — |
| T16 | `dropHandled` or deadline | `hide(.dropped)` / `hide(.lingerExpired)` + idle |
| T17/T18 | `escape` / `spaceChanged` in `wheel` → `live`; `escape` in `releasing` → idle | `hide(.escape)` / `hide(.spaceChanged)` |
| T19 | `with(config:)` | state kept; new masks apply from the next edge |

`edge` = `!mods.subtracting(previous).isEmpty`. `previous` starts as `∅` when `honorsModifierHeldAtDragStart`, else as
the modifiers held at mouse-down. Key releases are never edges, so they never change the wheel.

`TriggerMachine.swift` (complete):

```swift
import ZivletCore

/// Pure trigger state machine (03a §1.4). Transition numbers T1…T19 refer to that table.
public struct TriggerMachine: Sendable, Equatable {
    public let config: TriggerConfig
    public let state: TriggerState

    public init(config: TriggerConfig = TriggerConfig(), state: TriggerState = .idle) {
        self.config = config
        self.state = state
    }

    /// T19: new bindings apply from the next edge; state is kept.
    public func with(config: TriggerConfig) -> TriggerMachine { TriggerMachine(config: config, state: state) }

    public func step(_ event: TriggerEvent) -> TriggerStep {
        switch (state, event) {
        case (.idle, .sample(let s)): idle(s)
        case (.pressed(let snap, let held), .sample(let s)): pressed(s, snap: snap, held: held)
        case (.detecting(let snap, let held, let deadline), .sample(let s)):
            detecting(s, snap: snap, held: held, deadline: deadline)
        case (.passive, .sample(let s)): s.primaryButtonDown ? stay() : toIdle()
        case (.live(let live), _): self.live(live, event)
        case (.wheel(let wheel), _): self.wheel(wheel, event)
        case (.releasing(let mode, let deadline), _): releasing(mode, deadline: deadline, event)
        default: stay()
        }
    }

    // MARK: helpers shared by the extensions

    func go(_ state: TriggerState, _ effects: [TriggerEffect] = []) -> TriggerStep {
        TriggerStep(next: TriggerMachine(config: config, state: state), effects: effects)
    }

    func stay(_ effects: [TriggerEffect] = []) -> TriggerStep { go(state, effects) }

    /// T3 / T14 / T16 tail: back to idle; the host keeps only its mouse-down monitor.
    func toIdle(_ leading: [TriggerEffect] = []) -> TriggerStep {
        go(.idle, leading + [.stopSampler, .removeDragMonitors])
    }

    static func isEdge(_ mods: ModifierMask, previous: ModifierMask) -> Bool {
        !mods.subtracting(previous).isEmpty
    }

    // MARK: T1, T2, T4, T5

    private func idle(_ s: InputSample) -> TriggerStep {
        guard s.source == .mouseDown, s.primaryButtonDown else { return stay() }
        return go(.pressed(snapshot: s.dragChangeCount, held: s.modifiers), [.installDragMonitors])
    }

    private func pressed(_ s: InputSample, snap: Int, held: ModifierMask) -> TriggerStep {
        guard s.primaryButtonDown else { return toIdle() }
        guard s.source == .mouseDragged else { return stay() }
        let deadline = s.uptime + config.detectionWindow
        return go(.detecting(snapshot: snap, held: held, deadline: deadline), [.removeDraggedMonitor, .startSampler])
    }

    private func detecting(_ s: InputSample, snap: Int, held: ModifierMask, deadline: Duration) -> TriggerStep {
        guard s.primaryButtonDown else { return toIdle() }
        if s.dragChangeCount != snap {
            guard s.dragHasFileTypes else { return go(.passive, [.stopSampler]) }
            let previous: ModifierMask = config.honorsModifierHeldAtDragStart ? [] : held
            let live = TriggerState.Live(
                changeCount: s.dragChangeCount, summary: nil, previous: previous,
                liveStart: s.uptime, pendingEdge: false, queued: nil, location: s.location)
            return go(.live(live), [.probePayload(changeCount: s.dragChangeCount)])
        }
        return s.uptime >= deadline ? go(.passive, [.stopSampler]) : stay()
    }
}
```

`TriggerMachine+Live.swift` (complete):

```swift
import ZivletCore

// T3, T6–T9: file drag in progress, no wheel yet.
extension TriggerMachine {
    func live(_ live: TriggerState.Live, _ event: TriggerEvent) -> TriggerStep {
        switch event {
        case .sample(let s): liveSample(live, s)
        case .payload(let count, let summary) where count == live.changeCount: livePayload(live, summary)
        default: stay()
        }
    }

    private func liveSample(_ live: TriggerState.Live, _ s: InputSample) -> TriggerStep {
        guard s.primaryButtonDown else { return toIdle() }
        let pending = live.pendingEdge || Self.isEdge(s.modifiers, previous: live.previous)
        // Edges inside the debounce window are held and fire at the mark with the then-current set.
        guard pending, s.uptime - live.liveStart >= config.edgeDebounce else {
            return go(.live(live.observing(s, pendingEdge: pending)))
        }
        let next = live.observing(s, pendingEdge: false)
        guard let mode = config.bindings.mode(matching: s.modifiers) else { return go(.live(next)) }
        guard let summary = live.summary else { return go(.live(next.queueing(mode))) }  // T6
        return show(mode, live: next, summary: summary)  // T8 / T9
    }

    private func livePayload(_ live: TriggerState.Live, _ summary: DragSummary) -> TriggerStep {
        let next = live.receiving(summary)
        guard let mode = live.queued else { return go(.live(next)) }  // T7
        return show(mode, live: next, summary: summary)
    }

    /// T8 and T9 both show; a non-accepting wheel renders its empty-state pill and refuses drops.
    private func show(_ mode: WheelMode, live: TriggerState.Live, summary: DragSummary) -> TriggerStep {
        let wheel = TriggerState.Wheel(
            mode: mode, changeCount: live.changeCount, summary: summary,
            previous: live.previous, anchor: live.location)
        return go(.wheel(wheel), [.show(mode, at: live.location)])
    }
}
```

`TriggerMachine+Wheel.swift` (complete):

```swift
import ZivletCore

// T10–T18: wheel visible, then the release window.
extension TriggerMachine {
    func wheel(_ wheel: TriggerState.Wheel, _ event: TriggerEvent) -> TriggerStep {
        switch event {
        case .sample(let s): wheelSample(wheel, s)
        case .escape: backToLive(wheel, hide: .escape)  // T17
        case .spaceChanged: backToLive(wheel, hide: .spaceChanged)  // T18
        default: stay()
        }
    }

    func releasing(_ mode: WheelMode, deadline: Duration, _ event: TriggerEvent) -> TriggerStep {
        switch event {
        case .dropHandled: toIdle([.hide(.dropped)])  // T16
        case .escape: toIdle([.hide(.escape)])  // T17 (button up)
        case .sample(let s) where s.uptime >= deadline: toIdle([.hide(.lingerExpired)])
        default: stay()
        }
    }

    private func wheelSample(_ wheel: TriggerState.Wheel, _ s: InputSample) -> TriggerStep {
        guard s.primaryButtonDown else {
            guard s.pointerInsideWheel else { return toIdle([.hide(.buttonUp)]) }  // T14
            return go(.releasing(mode: wheel.mode, deadline: s.uptime + config.releaseTimeout))  // T15
        }
        let next = wheel.with(previous: s.modifiers)
        guard Self.isEdge(s.modifiers, previous: wheel.previous),
            let mode = config.bindings.mode(matching: s.modifiers)
        else { return go(.wheel(next)) }  // T13
        if mode == wheel.mode {
            return config.retapClosesWheel
                ? backToLive(next, hide: .sameModifierRetap)  // T10
                : go(.wheel(next))
        }
        guard wheel.summary.acceptedModes.contains(mode) else {
            return go(.wheel(next), [.reject(mode, .noItemsForMode)])  // T12
        }
        return go(.wheel(wheel.with(mode: mode, previous: s.modifiers)), [.switchTo(mode)])  // T11
    }

    /// Back to `live` with the summary kept; the debounce does not apply again.
    private func backToLive(_ wheel: TriggerState.Wheel, hide: HideReason) -> TriggerStep {
        let start = Duration.zero - config.edgeDebounce
        let live = TriggerState.Live(
            changeCount: wheel.changeCount, summary: wheel.summary, previous: wheel.previous,
            liveStart: start, pendingEdge: false, queued: nil, location: wheel.anchor)
        return go(.live(live), [.hide(hide)])
    }
}
```

#### 6b.4 Verify green

```bash
swift test --filter ZivletTriggerTests 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: `✔ Test run with 29 tests in 3 suites passed` [critic3: was 28; the held-modifier pair became three tests]. The property suite runs 400 seeded traces; a failure prints
the seed, and the same seed reproduces it.

#### 6b.5 Commit

```bash
git add Packages/ZivletKit
git commit -s -m "feat(trigger): add pure TriggerMachine with press-edge exact match and release window"
```

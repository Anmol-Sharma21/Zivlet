# 16d — M5b Stream D, part 1: notch proximity, drag-trace recorder, replay harness (NB5)

Part of [16-implementation-plan-m5b](16-implementation-plan-m5b.md). Conventions: index §6. Prototype numbers:
index §3.5–§3.6. Acceptance: 05 rows P2-197 (the remainder) and P2-143 ("P-N1 spike thresholds"). Swift below is
specification-grade and was not compiled.

What this part can and cannot show: the replay harness runs the detector on **synthetic** traces made from the
recorded 14-inch display fixture and on the constructed 1080p display, and on **recorded** traces when the owner has
made them. The P2-197 bar (≥ 95 % of notch-bound drags detected, 0 accidental opens over 200 normal drags) is
judged only on recordings (OS-M5b-1). Nothing in this part may claim it passed.

---

## Task D1 — `NotchProximity` (D-M5b-9)

| Field | Value |
|---|---|
| Goal | Pure value in `ZivletTrigger`. `Config { margin = 40, dwell = 100 ms, maxSpeed = 800 pt/s, release = 24 }` with `static let provisional`; `Zone { display: UInt32, rect: Rect2D }` (global points, y up, the margin already applied by D2). `NotchProximity(zones:config:)`, `observing(_ sample: InputSample) -> (NotchProximity, NotchProximityEvent?)` with events `.entered(display:)` and `.left(display:)`. It enters when the pointer has stayed inside one zone, at a speed at or under `maxSpeed` between consecutive samples, for `dwell`; the clock restarts when it leaves the zone or moves faster. Once entered, `.left` comes when the pointer is more than `release` outside the zone (the open drop target covers the zone, so small slips do not flicker). `reset()` at the end of a drag; `replacingZones(_:)` on display changes. Samples with a non-increasing uptime are ignored |
| Acceptance | table tests: a fast pass across the housing does not enter; resting 100 ms enters on the sample that reaches 100 ms; 99 ms does not; a slow drift across the zone at 900 pt/s does not enter; leaving 23 pt outside keeps it entered, 25 pt sends `.left`; two zones on two displays report the right display |
| Effort | S |

**Files:** create `Sources/ZivletTrigger/NotchProximity.swift`, `Tests/ZivletTriggerTests/NotchProximityTests.swift`.

```swift
@Suite("Notch proximity (P2-143, D-M5b-9)")
struct NotchProximityTests {
    let zone = NotchProximity.Zone(display: 1, rect: Rect2D(x: 750, y: 1131, width: 300, height: 38))

    @Test func restingOnTheHousingEntersAfterTheDwell() {
        let samples = Samples.rest(at: Point2D(x: 900, y: 1150), from: .zero, for: .milliseconds(100), hz: 120)
        let events = NotchProximity(zones: [zone], config: .provisional).events(for: samples)
        #expect(events == [.entered(display: 1)])
    }

    @Test func aPassOnTheWayToTheMenuBarOpensNothing() {
        let samples = Samples.line(from: Point2D(x: 600, y: 900), to: Point2D(x: 1200, y: 1168), over: .milliseconds(300))
        #expect(NotchProximity(zones: [zone], config: .provisional).events(for: samples).isEmpty)
    }

    @Test func smallSlipsDoNotClose() { /* entered; move 23 pt below the zone: no .left; 25 pt: .left */ }
}
```

RED: `cannot find 'NotchProximity' in scope`. Commit `feat(trigger): detect a file drag resting at the notch`.

---

## Task D2 — `IslandLayout.trayZone(on:margin:)`

| Field | Value |
|---|---|
| Goal | Pure in `ZivletNotchCore`: on a display with a housing, the housing's rectangle widened by `margin` on each side, as tall as the housing, at the display's top (global, y up); on a display without one, the menu-bar band (from `visibleFrame.maxY` to `frame.maxY`) across the pill's collapsed width plus `margin` on each side, centred. The app passes `NotchProximity.Config.provisional.margin`, so the constant lives in one place |
| Acceptance | the recorded fixture `mbp14MoreSpace` gives `Rect2D(x: 750, y: 1131, width: 300, height: 38)`; `noNotch1080` gives `Rect2D(x: -1100, y: 1055, width: 280, height: 25)`; `safeAreaWithoutAux` (no housing) uses the pill rule |
| Effort | S |

**Files:** create `Sources/ZivletNotchCore/IslandLayout+Tray.swift`, `Tests/ZivletNotchCoreTests/TrayZoneTests.swift`.

```swift
@Suite("Tray zone (D-M5b-9)")
struct TrayZoneTests {
    @Test func theRecordedNotchGivesTheHousingWidenedBy40() throws {
        #expect(IslandLayout.trayZone(on: try DisplayFixtures.mbp14MoreSpace(), margin: 40)
            == Rect2D(x: 750, y: 1131, width: 300, height: 38))
    }

    @Test func aDisplayWithoutANotchUsesTheMenuBarAboveThePill() throws {
        #expect(IslandLayout.trayZone(on: try DisplayFixtures.noNotch1080(), margin: 40)
            == Rect2D(x: -1100, y: 1055, width: 280, height: 25))
    }
}
```

RED: `type 'IslandLayout' has no member 'trayZone'`. Commit `feat(notch): add the tray's drop zone per display`.

---

## Task D3 — `DragTrace` model; synthetic generator and evaluator

| Field | Value |
|---|---|
| Goal | `DragTrace` in `ZivletTrigger` (`Codable`, validated): `schema` (1), `label` (`normal` \| `notch`), `display` (`TraceDisplay`: id, frame, visible frame, safe-area top, the two auxiliary areas, as `Rect2D` values, so the trigger module needs no notch types), `os` (the macOS version string), `samples` (`[TraceSample { t: milliseconds, x, y, down }]`). Validation on decode: schema 1, a known label, 2…20,000 samples, every number finite, `t` never decreasing, every point within the display frame widened by 100 pt. In `Tests/DragTraceSupport`: `SyntheticDrags` grows the prototype's generator (minimum-jerk paths at 120 Hz, overshoot, tremor, an end dwell; normal kinds anywhere / under the menu bar near the centre / the menu bar beside the housing / the Dock; notch-bound with a Gaussian endpoint spread, SD 50 pt, or a uniform ± 150 pt one), seeded by `SplitMix64`, for any `TraceDisplay`. `TraceEvaluator.score(_ traces:, zones:, config:) -> ProximityScore { detection: Double, accidental: Int, notchBound: Int, normal: Int }` (detection over `notch` traces, accidental opens over `normal` traces) |
| Acceptance | decoding refuses each invalid case with a typed error; a generated trace round-trips through JSON; the generator is deterministic for a seed; the evaluator counts a known hand-made set correctly |
| Effort | M |

**Files:** create `Sources/ZivletTrigger/DragTrace.swift`, `Tests/DragTraceSupport/SyntheticDrags+Paths.swift`,
`Tests/DragTraceSupport/TraceEvaluator.swift`, `Tests/ZivletTriggerTests/DragTraceTests.swift`,
`Tests/ZivletTriggerTests/TraceEvaluatorTests.swift`.

```swift
@Suite("Drag traces (P2-197 recordings)")
struct DragTraceTests {
    @Test(arguments: DragTraceFixtures.invalid)
    func invalidTracesAreRefused(_ json: String) {
        #expect(throws: DragTraceError.self) { try JSONDecoder().decode(DragTrace.self, from: Data(json.utf8)) }
    }

    @Test func aSyntheticTraceRoundTrips() throws {
        var rng = SplitMix64(seed: 197)
        let trace = SyntheticDrags.notchBound(on: .mbp14, spread: .gaussian50, &rng)
        #expect(try JSONDecoder().decode(DragTrace.self, from: JSONEncoder().encode(trace)) == trace)
    }
}
```

RED: `cannot find 'DragTrace' in scope`. Commits `feat(trigger): add the drag-trace format` and `test(trigger):
generate synthetic drags from the recorded display`.

---

## Task D4 — Replay harness; `make drag-replay`

| Field | Value |
|---|---|
| Goal | `NotchProximityReplayTests`: (1) **synthetic acceptance**: five seeded sets of 200 normal + 50 notch-bound drags with the Gaussian spread, on the recorded 14-inch fixture and on the constructed 1080p display (pill zone); every set must reach detection ≥ 0.95 and 0 accidental opens with `Config.provisional`; (2) **recorded**: when `ZIVLET_DRAG_TRACES` names a folder, every `*.json` in it is decoded and validated (an invalid file fails the test with its name and reason), zones come from each trace's own display, and the P2-197 bar applies: ≥ 50 `notch` traces with detection ≥ 0.95, ≥ 200 `normal` traces with 0 accidental opens. Without the variable the recorded test is skipped with a note that says so. `make drag-replay` runs the suite; `make drag-replay TRACES=<folder>` adds the variable |
| Acceptance | the synthetic suite passes on the provisional constants (if the Swift generator's seeds give a different result from the prototype, retune `Config` here and record the numbers in the commit message); the recorded test fails on a folder with an invalid trace and on a folder with too few traces |
| Effort | S |

**Files:** create `Tests/ZivletTriggerTests/NotchProximityReplayTests.swift`; modify `Makefile` (`drag-replay`).

```make
# NB5: the notch-proximity rule over synthetic traces; with TRACES=<folder>, also over recorded ones (OS-M5b-1).
drag-replay:
	$(ENV) $(NATIVE) cd "$$KIT" && ZIVLET_DRAG_TRACES="$(TRACES)" swift test --filter NotchProximityReplayTests
```

RED: the suite fails to compile until `TraceEvaluator` and the fixtures exist, then fails on the recorded case
fixtures (a deliberately short folder in `TempDir`). Commit `test(trigger): replay synthetic and recorded drags
through the notch-proximity rule`.

---

## Task D5 — `zivlet-traces` tuning tool

| Field | Value |
|---|---|
| Goal | A pure `ProximityTuning.grid(traces:margins:dwells:speeds:) -> [ProximityTuning.Row]` in `ZivletTrigger` (rows sorted by accidental opens, then detection), and a dev executable `zivlet-traces` (not shipped, not in the coverage gate, like `zivlet-bench`): `zivlet-traces report <folder>` prints the provisional rule's score; `zivlet-traces tune <folder>` prints the grid (margins 0/20/40/60/80, dwells 0/50/100/150/200 ms, speeds 400/800/1600/none). Output through `FileHandle.standardOutput`, no `print`; invalid files are listed with their reasons and left out |
| Acceptance | `ProximityTuning` tests on a hand-made set; `swift run zivlet-traces report <TempDir with two synthetic traces>` exits 0 (a test calls the tool's entry function, not a process) |
| Effort | S |

**Files:** create `Sources/ZivletTrigger/ProximityTuning.swift`, `Sources/zivlet-traces/main.swift`,
`Tests/ZivletTriggerTests/ProximityTuningTests.swift`; modify `Package.swift` (executable target, deps
`ZivletTrigger`, `ZivletCore`, `strict`).

RED: `cannot find 'ProximityTuning' in scope`. Commit `feat(tools): tune the notch-proximity rule on recorded
drags`.

---

## Task D6 — DEBUG drag-trace recorder (D-M5b-10)

| Field | Value |
|---|---|
| Goal | `DragTraceRecorder` in `ZivletTriggerHost`, compiled only under `#if DEBUG`: it collects the `onLiveSample` samples of one drag and, on `onDragEnded`, writes one `DragTrace` (label from the launch flag; the display under the drag's first sample, from an injected display closure) to its folder: `~/Library/Application Support/Zivlet/DragTraces/`, folder 0700, file 0600, name `<yyyyMMdd-HHmmss>-<label>-<n>.json`. Caps: 20,000 samples per drag (the rest dropped, the trace marked truncated and refused by D4's validation), 2,000 files per folder (then it stops and logs once). `App/DragTraceRecording.swift` (`#if DEBUG`) reads `-ZivletRecordDragTraces normal\|notch`, logs `DragTrace: recording notch` and `DragTrace: saved 312 samples` (public; counts and labels only, never a path or a name), and does nothing without the flag. `check-release-paths.sh` refuses the flag in a Release binary (the B10 script test grows one case). The QA list documents it (E1 §R) |
| Acceptance | recorder tests on `TempDir`: one drag → one valid file with mode 0600 in a 0700 folder; the 20,001st sample is dropped; no flag → no file; the release scan refuses the flag |
| Effort | S |

**Files:** create `Sources/ZivletTriggerHost/DragTraceRecorder.swift`, `App/DragTraceRecording.swift`,
`Tests/ZivletTriggerHostTests/DragTraceRecorderTests.swift`; modify `App/AppDelegate.swift`,
`Scripts/check-release-paths.sh`, `Scripts/tests/test-release-flags.sh`.

```swift
#if DEBUG
@Suite("Drag-trace recorder (D-M5b-10)")
@MainActor
struct DragTraceRecorderTests {
    @Test func oneDragWritesOnePrivateValidTrace() throws {
        let dir = try TempDir()
        let recorder = DragTraceRecorder(folder: dir.url.appending(path: "DragTraces"), label: .notch,
                                         display: { _ in TraceDisplay.mbp14 })
        for sample in Samples.rest(at: Point2D(x: 900, y: 1150), from: .zero, for: .milliseconds(200), hz: 120) {
            recorder.observe(sample)
        }
        let file = try #require(recorder.dragEnded())
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try JSONDecoder().decode(DragTrace.self, from: Data(contentsOf: file)).label == .notch)
    }
}
#endif
```

RED: `cannot find 'DragTraceRecorder' in scope`. Commit `feat(app): record drag traces in Debug builds when asked`.

---

## Task D7 — Pre-drop reads stay on the pasteboard (C4, D-M5b-4)

| Field | Value |
|---|---|
| Goal | Make D-M5b-4 a test, not a promise: every code path the box and the tray run while a drag is in flight (`BoxIntake.preview`, the drop view's `draggingEntered`/`draggingUpdated`, the tray client's proximity and drop-target handling once D10 lands) runs against failing fakes of `BookmarkMaking`, `ThumbnailMaking` and `PromiseReceiving` that record a test failure when called. Record the C4 answer in `docs/plan/qa/drop-box.md` §C4 from index §3.5, and add rows C4a–C4d for what the prototype could not settle |
| Acceptance | the tests pass; the QA rows exist with steps and expected results |
| Effort | S |

**Files:** create `Tests/ZivletBoxTests/PreDropReadTests.swift`; extended in D10 for the tray; the QA rows land with
E1.

| QA row | Check | Expected |
|---|---|---|
| C4a | Drag files from Downloads, Desktop, Documents and iCloud Drive (one evicted file among them) to the tray and to the panel, Zivlet freshly installed (or its TCC entries reset by the owner with `tccutil reset All app.zivlet.Zivlet`) | no prompt while dragging; note any prompt after the drop and which action raised it |
| C4b | Quit and relaunch with those items in the box; open the box | note whether thumbnails raise a folder prompt; if so, OP-M5b-3 decides |
| C4c | An evicted iCloud file in the box: open the box, then Quick Look it | note whether the thumbnail or Quick Look downloads it (the prototype showed metadata and bookmarks do not) |
| C4d | A USB drive's files in the box; eject the drive; open the box | no prompt while dragging; after ejecting, the items show "not connected", not "missing" |

Commit `test(box): nothing reads the dragged files before the drop`.

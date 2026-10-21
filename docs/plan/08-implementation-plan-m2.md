# 08 — M2 implementation plan: trigger + wheel running in a dev app build (TDD)

Date: 2026-10-21. Status: ready to execute. Milestone: **M2** of [05 §2](05-task-list.md) ("Trigger + wheel running in
a dev app build"). This file is the index. The tasks are in eight parts, each under 800 lines, because the verified
test and source files are embedded verbatim:

| Part | Tasks |
|---|---|
| [08a](08a-m2-package-placement-model.md) | 1 Shell targets · 2 Panel placement · 3 WheelModel, hub label, WheelSelection |
| [08b](08b-m2-negotiation-trigger-host.md) | 4 Drop negotiation and tick gate · 5 TriggerHost logic |
| [08c](08c-m2-trigger-adapters.md) | 6 AppKit monitors, sampler, watchdog, Esc hot key |
| [08d](08d-m2-wheel-store.md) | 7 Accent palette, themes, synthesized tick, WheelStore |
| [08e](08e-m2-drag-payload-demo.md) | 8 Drag payload reader and demo scenario |
| [08f](08f-m2-wheel-views.md) | 9 Petal shapes and the Glass/Solid SwiftUI wheel |
| [08g](08g-m2-panel-controller.md) | 10 WheelPanel, WheelDropView, WheelController |
| [08h](08h-m2-app-qa-exit.md) | 11 App wiring and DEBUG demo · manual real-drag QA · M2 exit check |

Inputs: [01-prd](01-prd.md) (FR-1…FR-6, FR-16, FR-22…FR-27, NFR-1…NFR-6), [02-architecture](02-architecture.md) §4–§7,
[03a](03a-system-design-interaction.md) §1 (trigger) and §2 (wheel), [05-task-list](05-task-list.md) (M2 = M1 +
P0-40…P0-43; spikes P0-31/P0-32 started), [design/14](../design/14-app-platform.md) §1–§3, the M1 plan
[06](06-implementation-plan-m1.md) (format and conventions).

Clean-room rule: every value below is a behaviour or a number from Zivlet's own docs. No code, assets, sounds, colours
or UI strings from the reference app or from Open-Tangerine are used. The highlight tick is synthesized in code
(`ToneSynth`). The accent is the user's system accent colour, not a fixed brand colour (D-M2-4). Code cites only plan/
and design/ docs.

---

## 1. Verification status of this plan

Every code block in 08a–08h was compiled and run on 2026-10-21 on the dev Mac (macOS 27.0 26A428, Xcode 27.0
27A266a, Swift 6.4.0.34.1, SDK MacOSX27.0, XcodeGen 2.45.4) in a scratch clone of `main` at `d9dd632`, before this
plan was written. Test files and complete sources are the verified files, embedded verbatim by script.

| Check | Result |
|---|---|
| `make test` | 238 test functions, all pass: 133 from M1 (unchanged) + 105 new (WheelCore +29 → 53, TriggerHost 24, Wheel 52) |
| `make coverage` (gate 80 % per module, now six modules) | ZivletCore 97 %, ZivletTrigger 100 %, ZivletWheelCore 99 %, EngineMedia 97 %, **ZivletTriggerHost 88 %**, **ZivletWheel 94 %**; exit 0 |
| `make lint` (`swift format lint --strict`) | 0 findings (Sources, Tests and App) |
| `make app` Debug and Release | `** BUILD SUCCEEDED **` both; `flags=0x10002(adhoc,runtime)`; `LSUIElement` true; Release binary has no `DebugHUD` symbol (`nm`) |
| Task-by-task replay in a fresh clone | Every RED step failed to compile with the stated `cannot find …` errors; every GREEN count matched; the final tree was identical to the reference (`diff -rq` empty) |
| Liquid Glass API names | Checked in `MacOSX27.0.sdk/…/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`: `glassEffect(_:in:)`, `GlassEffectContainer(spacing:content:)`, `glassEffectID(_:in:)`, `glassEffectTransition(_:)` with `.matchedGeometry`, `Glass.regular/.clear/.identity`, `.tint(_:)`, `.interactive(_:)`; all `macOS 26.0` |
| AppKit under `swift test` | `NSPanel` (level 101, behaviour `0x159`), `ImageRenderer` of glass and Solid views, `NSScreen.displayLink` (24 ticks in 200 ms = 120 Hz), global mouse monitors and Carbon `RegisterEventHotKey(kVK_Escape)` all work in-process |
| DEBUG demo | `make demo` for convert/tools/actions in Glass and Solid: wheel at screen centre, highlight drawn, `Wheel shown: <mode>, <n> slices, <theme>` notice in the unified log; screenshots inspected (petals distinct at container spacing 6, glass refracts the windows behind, hub disc, empty-state pill) |
| Idle cost (01-prd NFR-4) | App launched with no drag: `top -stats cpu,idlew` → 0.0 % CPU, **0 idle wake-ups** per 5 s sample, 25 MB |
| Largest file / longest function | 204 lines (a test file) / under 50 lines |

**Not verifiable in this session** (no Accessibility permission, so no synthetic drags; no trackpad feel): real Finder
drags, modifier taps during a drag, haptics, the tick's loudness, Esc during a live Finder drag, full-screen Spaces and
multi-display placement on real hardware. The owner runs the manual checklist in [08h §M2-QA](08h-m2-app-qa-exit.md)
for these; every row maps to an FR or a spike.

Implementation sections give the complete verified files. An engineer may write different bodies as long as the tests
pass and the rules in §4 hold.

---

## 2. Task index

| # | Task | Module | 05 rows | Part | Tests added |
|---|---|---|---|---|---|
| 1 | Shell targets `ZivletTriggerHost`, `ZivletWheel` (main-actor default) + coverage gate | Package | P0-02 (shell subset) | 08a | 2 smoke (deleted in 5, 7) |
| 2 | Pure panel placement: disk + 8 pt inside `visibleFrame` | WheelCore | P0-26 | 08a | 9 |
| 3 | `WheelModel` reducer, hub label, byte sizes, `WheelSelection` | WheelCore | P0-27, P0-43 (selection) | 08a | 15 |
| 4 | Drag-operation negotiation, highlight tick gate | WheelCore | P0-28 | 08b | 5 |
| 5 | `TriggerHost`: OS ports → `TriggerMachine` → effects | TriggerHost | P0-40 | 08b | 15 |
| 6 | System adapters: monitors, display link, watchdog, Esc, Space change | TriggerHost | P0-40, P0-31 (instruments) | 08c | 9 |
| 7 | Accent palette, themes, synthesized tick, haptics, `WheelStore` | Wheel | P0-42 | 08d | 18 |
| 8 | Drag payload reader (per change count, off-main stat), demo scenario | Wheel | P0-41, P0-43 | 08e | 11 |
| 9 | `PetalShape`, Glass and Solid `WheelView` | Wheel | P0-42 | 08f | 9 |
| 10 | `WheelPanel`, `WheelDropView`, `WheelController` | Wheel | P0-41 | 08g | 14 |
| 11 | AppKit app: composition root, status menu, DEBUG demo + HUD, `make demo` | App | P0-43 | 08h | build + demo check |

Dependency order is linear. Totals per test bundle after each GREEN step: WheelCore 33 → 48 → 53; TriggerHost 15 → 24;
Wheel 18 → 29 → 38 → 52.

### 2.1 Not in this plan (follow-ons)

| Item | Why it is separate | Suggested home |
|---|---|---|
| P0-22 JSON traces and the P0-40 "Record trigger trace" Debug menu | Needs the trace codec; M1 tests use the in-code DSL | M1b plan |
| P0-31 / P0-32 spikes | **Started** by this build: QA rows Q12, Q21, Q23 (P-T1/T2/T3/T6) and Q20 (P-W1). P-T4 latency needs an `OSSignposter` interval from sample uptime to first frame | spike docs `docs/plan/spikes/` |
| P0-17 `JobRequest` | Not planned yet; M2 logs a typed `WheelSelection` instead (D-M2-3) | M3 plan |
| `draggingEntered` strict URL refresh that rebuilds slots (03a §2.5 row 1) | M2 re-validates at drop only and refuses a changed set | M3 |
| File promises (Mail, Photos, browsers; FR-2, P2) | Promise-only drags open the wheel with "Nothing to work on yet" | P2 |
| Keyboard mode (03a §2.8), Settings toggles (sound, haptics, Esc opt-in), golden snapshot images | P1 features; M2 uses render + pixel assertions instead of PNG goldens | P1 |
| P0-03 import gate, P0-07 CI | Shell tests need a window-server session: CI must run them on a logged-in runner (P0-34) | M1b / CI plan |

---

## 3. Decisions taken while planning

| # | Topic | Sources disagree / are silent | This plan uses | Why |
|---|---|---|---|---|
| D-M2-1 | P0-26…P0-28 | 06 §2.1 left them for an M1b plan | Planned here as Tasks 2–4 | M2 needs them; they are pure and small |
| D-M2-2 | Placement | 14 §1.4 "do not clamp the centre"; 05 P0-26 "372 panel clamped to `visibleFrame`"; 03a §2.1 "shift only if the **disk** + 8 pt would leave `visibleFrame`" | 03a §2.1 (= 01-prd FR-24 P1): disk + 8 pt; panel may overhang | 03a is the newest and FR-24 P1 is written against it; offset ≤ 134 pt at a corner |
| D-M2-3 | Drop result | 05 M2 exit / P0-43 "logs a `JobRequest`" | Typed `WheelSelection {mode, target, urls}` logged as summary (public) + JSON (private) and shown in the DEBUG HUD | P0-17 is not planned; the selection is exactly what M3 turns into a request |
| D-M2-4 | Accent hue | 01-prd §5.5 "Zivlet accent (own token, design doc)"; no design doc defines one | `NSColor.controlAccentColor` as the base; light/dark stops by the 03a §2.7 recipe | No brand token exists. **[OWNER]** may set one later (one line in `AccentPalette.system`) |
| D-M2-5 | Tick sound | 03a §2.7 "original 20–40 ms sample"; owner rule: system sound names or code-synthesized tone | 24 ms sine burst (1318.5 Hz) generated by `ToneSynth`, played via System Sound Services, 35 ms spacing | No bundled asset; nothing derived from the reference app |
| D-M2-6 | Glass highlight | 14 §2.3 `.regular.tint(accent)` + `scaleEffect(1.05)` | Accent radial gradient behind the hot petal's label **and** `.tint`; the 1.05 growth lives in `PetalShape.grow` | Prototype screenshots: `.tint` alone is near-invisible on dark backdrops, and `scaleEffect` inside a `GlassEffectContainer` moved the glass off its petal |
| D-M2-7 | Hub | 03a §2.2: ring inner r 42.24 is a hole | An r 42.24 disc (glass, or opaque in Solid) under the hub label | Prototype: desktop text showed through behind the hub label; own design |
| D-M2-8 | Esc | 03a §1.8: opt-in in Settings › Keyboard | Carbon hot key registered only while the wheel is visible, always on in M2 | No Settings UI in M2; QA needs it (P-T3). P1 makes it the opt-in toggle |
| D-M2-9 | `flagsChanged` monitor | 03a §1.8: only if P-T2 shows no permission is needed | Off; `-ZivletFlagsMonitor YES` turns it on for the spike | NFR-3: no prompt in the default flow |
| D-M2-10 | App entry | M1 `ZivletApp` used SwiftUI `MenuBarExtra` | AppKit `@main enum ZivletMain` + `NSStatusItem` (14 §3.1) | Composition root and DEBUG menus need AppKit; the SwiftUI scene is removed |
| D-M2-11 | Button state | 03a §1.2 reads `pressedMouseButtons` per sample | Mouse events state the button (down/dragged → true, up → false); frames read `pressedMouseButtons` | A quick click can be over before the monitor callback reads the hardware state |
| D-M2-12 | Log levels | — | `.notice` for "Wheel shown …" and "Wheel selection: …"; errors `.error`; paths `.private` | `.info` is not persisted, so `log show` (used by `make demo`) would miss it; NFR-6 |
| D-M2-13 | Window frames in tests | — | Assertions allow ≤ 1 pt | AppKit rounds window frames to whole points (−52.08 → −52 observed) |

---

## 4. Conventions for every task

M1 conventions apply unchanged ([06 §4](06-implementation-plan-m1.md)): `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
TDD loop, `git commit -s` with a conventional message and no `Co-Authored-By`, immutable values, files < 800 lines,
functions < 50, typed errors, no `print`. Additions for the two shell modules:

| Item | Rule |
|---|---|
| Isolation | `ZivletTriggerHost`, `ZivletWheel` and their test targets use `shell = strict + [.defaultIsolation(MainActor.self)]` (02 §6.1). `Shape`, `GeometryEffect` and the off-main classifier are marked `nonisolated`; the stat pass is `@concurrent` |
| Mutable state | Only in shell objects (`TriggerHost`, `WheelStore`, `WheelController`, schedulers), and only by replacing immutable values (`machine = result.next`, `model = model.applying(hit)`). `PetalShape.grow` is the one `var` in a value type, because SwiftUI animates `animatableData` |
| Test environment | Shell tests create windows, display links and a Carbon hot key: run them in a logged-in GUI session (the dev Mac; a CI runner must be logged in). Suites that touch shared AppKit state are `.serialized` |
| RED expectation | A missing type is a compile error, for example `error: cannot find 'PanelPlacer' in scope` |
| GREEN command | `swift test --filter <TestTarget> 2>&1 \| grep -E "Test run with\|error: "` |
| After GREEN | `swift format format -i -r Sources Tests` (from `Packages/ZivletKit`), then `make lint` from `$REPO` |
| Logging | `Logger(subsystem: "app.zivlet.Zivlet", category: …)`; never log modifier state or key codes (03a §1.2); paths `.private` |

### 4.1 Layout after Task 11 (new and changed files only)

```text
App/ZivletMain.swift  AppDelegate.swift  StatusMenu.swift  DebugHUD.swift      (App/ZivletApp.swift deleted)
Makefile (demo target)   Scripts/coverage.sh (six gated modules)   Scripts/demo-wheel.sh
Packages/ZivletKit/Package.swift
  Sources/ZivletWheelCore/  PanelPlacer  WheelModel  HubLabel  WheelSelection  DropNegotiation  (+ WheelSlice init)
  Sources/ZivletTriggerHost/ TriggerPorts  TriggerHost  ModifierMask+AppKit  SystemInputReader  FrameSampler
                              EscapeHotkey  SystemTriggerScheduler
  Sources/ZivletWheel/      AccentPalette  WheelAppearance  ToneSynth  WheelFeedback  WheelStore  DragPayload
                              DemoScenario  PetalShape  WheelParts  WheelView  WheelPanel  WheelController
                              WheelController+Drop
  Tests/ZivletWheelCoreTests/  PanelPlacerTests  WheelModelTests  HubLabelTests  DropNegotiationTests
  Tests/ZivletTriggerHostTests/ TriggerFakes  TriggerHostTests  SystemAdapterTests
  Tests/ZivletWheelTests/   WheelFakes  AppearanceTests  WheelStoreTests  DragPayloadTests  WheelViewTests
                              WheelControllerTests
```

### 4.2 Runtime wiring (Task 11)

```text
NSEvent monitors / display link / watchdog / Carbon Esc / Space change
        │ TriggerSignal                                  ▲ SamplingPlan (only when it changes)
        ▼                                                │
  TriggerHost ── InputSample ──▶ TriggerMachine (M1, pure) ── effects
        │  probePayload(cc) → DragPayloadReader.summary (stat off-main) → .payload
        │  show / switchTo / reject / hide
        ▼
  WheelController ── PanelPlacer, SliceBuilder, WheelModel ──▶ WheelStore (@Observable) ──▶ WheelView (SwiftUI)
        ▲  WheelDropView (NSDraggingDestination): hit-test, DropNegotiation, URLs re-read at drop
        │  draggingEnded → TriggerHost.receive(.dropHandled)
        └─ delegate: AppDelegate → os.Logger + DEBUG HUD
```

---

## 5. Definition of done for this plan

- [ ] Tasks 1–11 committed in order, each with its own signed conventional commit.
- [ ] `make test` exits 0 with 238 tests; `make coverage` prints ≥ 80 % for all six gated modules; `make lint` exits 0.
- [ ] `make app` prints `** BUILD SUCCEEDED **` for Debug and Release; `make demo MODE=…` prints `OK:` for each mode.
- [ ] The owner has run the [08h](08h-m2-app-qa-exit.md) manual checklist on real hardware: rows Q1–Q11 and Q19 pass
      (the 05 M2 exit criteria), and the spike rows have results written to `docs/plan/spikes/`.
- [ ] No TCC prompt appeared during the checklist (01-prd NFR-3).

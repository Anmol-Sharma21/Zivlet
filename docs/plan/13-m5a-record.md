# 13 — M5a record: notch island core and Notch HUD

Date: 2026-10-23. Status: **tasks N1–N13 committed on `main`; not pushed**. The exit rows were run (§4): X1–X5 and
X7 pass; **X6 (idle CPU) does not pass** in the progress state, and the collapsed state is noisy on a loaded Mac
(§4, G-M5a-1). The owner rows Q1–Q22 ([qa/notch.md](qa/notch.md)) have not been run, so M5a is not "complete" in the
sense of [12 §6](12-implementation-plan-m5a-notch.md).

This is a record, not a plan. The plan is [12](12-implementation-plan-m5a-notch.md) with its parts
[12a](12a-m5a-notch-core.md) and [12b](12b-m5a-notch-hud.md); the design is [design/19](../design/19-notch.md). This
file says what M5a contains, how the work went, the gate numbers, the decisions and deviations added while building,
the known gaps and the owner steps.

Clean-room rule: unchanged. No code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch
or shelf app. Every string in the island, the Settings row, the status menu and the QA list is Zivlet's own.

---

## 1. What M5a contains

| Area | What is in `main` | Task |
|---|---|---|
| Shared geometry | `Rect2D` in `ZivletCore` next to `Point2D` (D-M5a-1); it imports CoreGraphics for its `CGRect` bridge (D-M5a-17) | N1, fix |
| `ZivletNotchCore` (pure) | `DisplayGeometry` with validated values and a recorded 14-inch fixture; `NotchGeometry` (housing from the auxiliary areas, the built-in latch); `IslandLayout` (tab below the housing, toast, expanded card with a 320 pt cap and scrolling, top-centre pill, display for a point); `IslandMachine` and `IslandMotion` (hover intent and grace, holds, menu command, measured height, wheel suppression, keys and Escape; table-driven tests); `IslandArbiter` (picker > tray > HUD per display); `DisplayGeometry.diagnosticsLine` | N1–N5, N12 |
| `ZivletNotch` (AppKit) | `IslandPanel` above the menu bar on every Space; `ScreenGeometryReader` with per-subscriber changes and the notch latch; `IslandHost` (generation token, shape-sized hover, measured height, one clock); `IslandHosts` (one pre-warmed host per display, sole owner of display changes, per-display withdrawal and expand, a surface report for the app's log lines) | N7, N10, N11 |
| Settings | `HUDPlacement` (`automatic`, `notch`, `nearDrop`), `HUDGroup`, store key and migration; Settings › General › Progress and results ("At the notch" / "At the top of the screen", "Near the drop"); the picker shows the resolved value and stores a choice | N6, N11 |
| `ZivletUI` | surface-free HUD content (`ResultCardContent`, `WorkingContent`, `ActionContent`) and the one-clock linger fix in `ResultHUD`; `NotchHUDBoard` (pure: items per display, lingers, holds, failure toast then tab, list rows, announcements, redraw throttle, display moves); `NotchHUD` (the island's `.hud` client) with the tab, toast, card and list views; `HUDPresenter` / `ActionPresenter`; `BatchRoutes`; `PlacementOverride`; the status-menu command; the DEBUG `IslandPreview` | N8–N11, N13 |
| App | `IslandWiring` builds one `ScreenGeometryReader`, one `IslandHosts` and one `NotchHUD`; conversions route per drop, actions per run; `-ZivletHUDPlacement` for one run; "Show Progress and Results" in the status menu; the wheel's shows and hides, Reduce Motion and VoiceOver or Switch Control reach the island; `Island: <surface>` and `Island: frame x y w h` log lines; displays in Copy Diagnostics | N11, N12 |
| Scripts and docs | `Scripts/m5a-exit.sh` (X1–X7), `Scripts/idle-cpu.sh`, `Scripts/demo-notch.sh` (`make notch-demo`), `Scripts/notch-idle.sh` (`make notch-idle`), `make notch-timing`, `make convert-demo PLACEMENT=…`, their script tests; `docs/plan/qa/notch.md` (Q1–Q22) | N13 |

## 2. Commits

Baseline `1716912`. The design and plan commits (`16f1857`, `b075774`, `68423b0`) come first. The build was done by
several agent sessions: the earlier ones stopped when the Mac slept, after committing N1–N9; the next one found
N10 half done in the working tree, read it, finished it from there, did N10–N13 and drafted this record, and stopped
during the third X6 run; the last one re-ran the gates, made the icon change below, ran X6 again and committed the
record.

| Task | Commits |
|---|---|
| N1 | `ad6bd2b` refactor(core): move Rect2D into ZivletCore · `f6bdd7f` chore(notch): modules and coverage gate |
| N2 | `e2a9d7d` feat(notch): display geometry and the notch housing |
| N3 | `e8a9e3c` feat(notch): island frames for the notch tab and the pill |
| N4 | `3f78011` feat(notch): island state machine |
| N5 | `117360a` feat(notch): arbiter |
| N6 | `750a0ff` feat(settings): choose where progress and results show |
| N7 | `f603e82` feat(notch): island panel and host |
| N8 | `7244211` refactor(ui): content and surface · `2f7259b` fix(ui): one clock for card lingers |
| N9 | `31631bc` feat(ui): Notch HUD board |
| N10 | `cf67696` feat(ui): Notch HUD shows progress, results and action toasts on the island |
| N11 | `ae615d6` feat(ui): Settings choice · `abb80cd` feat(ui): batch routes · `10049fa` feat(app): one island, routing per drop, Show Progress and Results |
| N12 | `5311216` feat(ui): display geometry in Copy Diagnostics |
| N13 | `d249d77` feat(app): DEBUG island preview · `9463cf5` test(scripts): exit runner, sampler, notch demo · `82cf17a` docs: QA list · this record |
| Found by the exit run | `89a9497` fix(core): Release builds compile again after the Rect2D move · `a1f6351` fix(scripts): hygiene row pattern · `bbc54ec` perf(notch): the measurer lets go of the content · `77927bc` perf(ui): one icon per file type |

Every commit since the baseline is signed off and has no `Co-Authored-By` (X7).

## 3. How the exit run changed the code

- **Release builds were broken since N1** (`make release-check` was not run between N1 and the exit run). With
  Foundation alone, `ZivletCore` saw `CGRect` through CoreFoundation's copy of the geometry types, and the optimized
  Release build of `ZivletWheel` and `ZivletNotch` crashed the compiler while reading back `Rect2D.init(_: CGRect)`.
  `Rect2D.swift` now imports CoreGraphics (D-M5a-17); `make release-check` passes.
- **X7 matched its own pattern**: the line that searches for the scratch-folder prefix contained it. Fixed.
- **X6 progress state**: the island's off-screen measurer kept the expanded view and laid it out with every published
  progress change. It now lets go after measuring; one 120 s sample went from about 1.6 % to 1.1 %. Still over the
  1 % limit (G-M5a-1).
- **X6 progress state, second look**: the tab asked the workspace for the file icon at every redraw, and so got a
  new image each time; it now keeps one per type (`77927bc`, with a failing test first). Run 3 below includes it.
  It made no clear difference: progress was +1.358 % over the baseline. A 20 s `sample` of the progress state put
  the main thread at about 0.8 % busy (about 120 of 14,331 samples): about half in the preview's own driver and the
  board's transitions, in unoptimized Debug code, and most of the rest in SwiftUI layout and drawing at the redraw
  rate. No single hot spot is left.

## 4. Gates and exit rows (2026-10-23, macOS 27.0, Xcode 27, M2 Pro 14-inch, Debug app)

| Row | Result | Numbers |
|---|---|---|
| X1 | pass | `make test lint coverage app release-check licence-gate` (and `make script-test`), last run at `77927bc`: 15 test bundles, 1105 tests (one earlier `make coverage` run on the busy Mac failed a test it did not name and passed when run again); coverage (lines) ZivletCore 98 %, ZivletTrigger 100 %, ZivletWheelCore 99 %, ZivletEngineKit 97 %, EngineMedia 97 %, EngineImage 95 %, ZivletRuntime 95 %, ZivletTriggerHost 92 %, ZivletWheel 96 %, ZivletActions 91 %, ZivletSettings 96 %, ZivletUI 94 %, **ZivletNotchCore 98 %, ZivletNotch 94 %**; size and licence gates OK |
| X2 | pass | `NotchHUDTimingTests` (≤ 50 ms with hosts built as the app builds them); the `drop→island` signpost is in the demo's log. Note G-M5a-4 on what the interval measures |
| X3 | pass | heic → jpg at the notch: `Island: collapsed`, `Island: frame 784 0 232 62`, `Island: toast`, `Island: frame 720 0 360 74`, `Result card: <private> · 1 KB → 4 KB`; screenshot `build/m5a-exit/notch-toast.png` |
| X4 | pass | the same demo with `nearDrop`: `Result card` line, no `Island:` line |
| X5 | pass | no tccd request with `preflight=no` for Zivlet while X2–X4 ran |
| X6 | **fail** | see below |
| X7 | pass | signed off, no `Co-Authored-By`, no changed source file ≥ 800 lines, no personal path added |

X6, CPU of the Debug app, 120 s per state, after 10 s to settle, minus the baseline ("Near the drop", no job). The Mac
was busy during every run (Spotlight indexing at about 100 % of a core, load average 3–12), so the same state moved by
up to 0.4 % between runs. These are Debug-build numbers. An earlier third run was stopped during the progress state
when its session ended (baseline 0.108 %, hidden +0.067 %, collapsed +0.084 %, both pass); run 3 is a full new run
(load average 6.3 at the start, 2.5 at the end).

| State (limit over baseline) | Run 1 (during the Release builds) | Run 2 | Run 3 (after the measurer and icon changes) |
|---|---|---|---|
| baseline | 0.008 % | 0.042 % | 0.000 % |
| hidden (0.1 %) | +0.017 % pass | +0.058 % pass | +0.075 % pass |
| collapsed, still (0.1 %) | +0.000 % pass | +0.400 % **fail** | +0.033 % pass |
| progress input at 10 Hz (1 %) | +1.592 % **fail** | +1.625 % **fail** | +1.358 % **fail** |
| stepped glyph (1 %) | +0.684 % pass | +0.858 % pass | +0.733 % pass |

## 5. Decisions added while building

D-M5a-1 … D-M5a-11 are in [12 §4](12-implementation-plan-m5a-notch.md).

| ID | Decision | Why |
|---|---|---|
| D-M5a-12 | One `HUDRoute` (`notch`, `nearDrop`) serves `BatchRoutes` and `PlacementOverride.defaultRoute` | A route is never `automatic`; one type keeps the two in step |
| D-M5a-13 | `ConversionWiring` forgets a batch's route only when Retry hands it on | The presenters do not report closes; a route is a few bytes, and forgetting on "finished" would let a stray late snapshot claim the next drop's route |
| D-M5a-14 | The `Island:` log lines come from the app through `IslandHosts.onSurface`; the frame is in screen-capture points (origin top left of the menu-bar display) | The notch modules stay free of the demo's needs, and `screencapture -R` can use the line as it is |
| D-M5a-15 | "Show Progress and Results" is always in the status menu and disabled while the island is empty | A fixed menu shape; the M4 menu test changed to include it |
| D-M5a-16 | The island learns of the wheel from the trigger's `show` and `hide` effects in `AppDelegate`, not from `WheelController` | D-M5a-6 without touching the wheel module |
| D-M5a-17 | `Rect2D.swift` imports CoreGraphics | Release builds (§3) |
| D-M5a-18 | DEBUG `-ZivletIslandPreview collapsed|progress|indeterminate|expanded|result|failure` puts a made-up job on the island | X6 and the screenshots need states that a conversion of a small fixture passes too quickly; Release builds do not contain it |

## 6. Deviations from the plan

- N10: the island views are `NotchTab`, `NotchToast`, `NotchCard` (with `NotchExpanded`, which picks the card or the
  list), `NotchList` and a shared `NotchGlyphs` file; the chrome from N7 already draws the black shape, the
  Increase Contrast outline and the accessibility group, so the views do not repeat them. `IslandHosts` gained
  `withdraw(_:on:)` and `expandRequested(on:)` (the accessibility action opens its own display's island).
- N11: `SettingsModel` exposes `hasBuiltInNotch`, `shownPlacement`, `choosePlacement(_:)` and `follow(_:)`; the tests
  use the existing `SettingsModel.preview` rather than a new `testModel`. `PlacementOverride.parse` takes the launch
  arguments' domain as `[String: Any]`. `StatusMenu.swift` needed no change (the menu model drives it).
- N13: X2 runs its own notch demo for the signpost check; X6 is `Scripts/notch-idle.sh` behind `make notch-idle`; the
  island preview became its own commit.

## 7. Known gaps

| ID | Gap | Next step |
|---|---|---|
| G-M5a-1 | X6 fails: progress input at 10 Hz costs about 1.1–1.6 % CPU over the baseline in the Debug app (limit 1 %), and the still states move by up to 0.4 % between runs on a busy Mac. The profile (§3) shows no single hot spot; about half the main-thread time is unoptimized Debug code | Re-run `make notch-idle` on a quiet Mac. If progress still fails, measure an optimized build (the island preview is Debug-only today, so this needs a preview that an optimized local build can show), or skip the board transition when a snapshot changes nothing that is drawn or announced |
| G-M5a-2 | A card opened with "Show Progress and Results" or the accessibility action, with no pointer over it, still leaves when a saved result's 4 s linger ends: only hover, VoiceOver focus and a drag hold (D-N13) | Owner rows Q18–Q20 decide whether the menu command should hold too |
| G-M5a-3 | A drag of the result thumbnail out of the island is held only because the pointer is over the island when it starts; the island gets no separate drag-began or drag-ended event | Q4 |
| G-M5a-4 | `NotchHUD.prepare(near:)` now runs when a batch's first snapshot claims its route (D-M5a-8), so the `drop→island` signpost measures first snapshot → island, not drop → island | Begin the interval at the drop in `ConversionWiring` if the full span is wanted |
| G-M5a-5 | The `-UITestFixture` path still shows its card on `ResultHUD` directly, whatever the placement | Route it if the UI test should cover the island |
| G-M5a-6 | P2-197's remainder (drag-near-notch detection over recorded drags, the pre-drop-read TCC/iCloud question) | M5b task NB5, as planned |

## 8. Owner steps

| ID | Step |
|---|---|
| OP-1 … OP-6 | As in [12 §7](12-implementation-plan-m5a-notch.md): milestone names, the second placement's label, hover timings, the QA run, more display fixtures, the collapsed look |
| O-M5a-1 | Run [qa/notch.md](qa/notch.md) Q1–Q22 on real hardware |
| O-M5a-2 | Re-run `make notch-idle` (X6) on a quiet Mac and decide on G-M5a-1 |
| O-M5a-3 | Review the commits and push |

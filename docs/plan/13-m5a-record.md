# 13 — M5a record: notch island core and Notch HUD

Date: 2026-10-23. Status: **tasks N1–N13 and the review fixes (§9) committed on `main`; not pushed**. The exit rows
were run (§4): X1–X5 and X7 pass; **X6 (idle CPU) does not pass** in the progress state, and the collapsed state is
noisy on a loaded Mac (§4, G-M5a-1). A review of M5a followed; §9 says what it found and what was done. The owner
rows Q1–Q26 ([qa/notch.md](qa/notch.md)) have not been run, so M5a is not "complete" in the sense of
[12 §6](12-implementation-plan-m5a-notch.md).

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
| Review fixes (§9) | `924471a` fix(notch): screen reader subscribers and duplicate screens · `b8b6f49` fix(notch): a keyed island holds and gives the keyboard back · `6af0fd1` fix(notch): place, Reduce Motion, new geometry · `a9549cc` fix(notch): requests wait for their display, empty display lists · `401eca5` fix(ui): long names and the card's sides · `a2562ea` fix(ui): no made-up display, spoken progress, drags · `abf72d0` fix(scripts): exit rows fail on a failing step, X5 · the commit that adds §9 and Q23–Q26 |

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

D-M5a-1 … D-M5a-11 are in [12 §4](12-implementation-plan-m5a-notch.md); D-M5a-19 … D-M5a-26 came with the review
fixes (§9.2).

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
| G-M5a-2 | **Closed by the review fixes (§9, D-M5a-19).** A card opened with "Show Progress and Results" or the accessibility action left when a saved result's 4 s linger ended | Q18–Q20 check that the hold is long enough |
| G-M5a-3 | **Closed by the review fixes (§9).** A drag of the result thumbnail was held only because the pointer was over the island; the island now hears the drag begin and end | Q4 |
| G-M5a-4 | `NotchHUD.prepare(near:)` now runs when a batch's first snapshot claims its route (D-M5a-8), so the `drop→island` signpost measures first snapshot → island, not drop → island | Begin the interval at the drop in `ConversionWiring` if the full span is wanted |
| G-M5a-5 | The `-UITestFixture` path still shows its card on `ResultHUD` directly, whatever the placement | Route it if the UI test should cover the island |
| G-M5a-6 | P2-197's remainder (drag-near-notch detection over recorded drags, the pre-drop-read TCC/iCloud question) | M5b task NB5, as planned |
| G-M5a-7 | The motion fixes of §9 (no sideways jump, corners and content inside the animation, Reduce Motion) are checked by tests of the model's values, not of drawn frames; whether SwiftUI renders the housing start state of `appear` at all is unverified (review LOW 1) | Q12 and Q24 on real hardware; if the first frame is wrong, flush the start state before animating |
| G-M5a-8 | The review's LOW findings listed in §9.5 are not fixed | Each has its next step there |
| G-M5a-9 | The 50 ms drop-to-island test has little margin on a loaded Mac: one run after the fixes measured 72 ms (§9.3). The X2 pass of §4 came from a runner that could not fail on that step; X1's `make test` did run the test then and passed | Re-run X2 on a quiet Mac; if it fails there, profile `NotchHUD.show` (not profiled yet) |

## 8. Owner steps

| ID | Step |
|---|---|
| OP-1 … OP-6 | As in [12 §7](12-implementation-plan-m5a-notch.md): milestone names, the second placement's label, hover timings, the QA run, more display fixtures, the collapsed look |
| O-M5a-1 | Run [qa/notch.md](qa/notch.md) Q1–Q26 on real hardware (Q23–Q26 were added for the review fixes, §9.6) |
| O-M5a-2 | Re-run `make notch-idle` (X6) on a quiet Mac and decide on G-M5a-1 |
| O-M5a-3 | Review the commits and push |
| O-M5a-4 | Decide the LOW findings of §9.5 that are design questions: the list rows' buttons (LOW 6) and the island's own progress bar (LOW 3, LOW 13) |

## 9. Review fixes

A review of M5a reported 18 findings rated HIGH or MEDIUM and 14 rated LOW. Each was checked against the code
before anything changed; none was wrong, though two MEDIUM findings describe the same `update(display:)` problem and
one suggested fix would not have worked (row 12). Where behaviour changed, a failing test came first and was seen to
fail. The work was done by one agent session after the record above was committed.

### 9.1 Findings and what was done

| # | Rating | Finding (short) | Result | Commit |
|---|---|---|---|---|
| 1 | MEDIUM | `ScreenGeometryReader.changes` never dropped a subscriber; every Settings open left a stream that buffered every later display change | Fixed: a stream removes itself when it ends and keeps only the newest list (D-M5a-26); test with a watch that is cancelled | `924471a` |
| 2 | MEDIUM | `IslandHost.update(display:)` kept stale insets, corners and scrolling, did not re-measure, and a shrink in flight put the panel back at the old frame | Fixed: refresh, re-measure, drop the running completion; completions work out the frame from the current surface | `6af0fd1` |
| 3 | MEDIUM | The island's spoken value stayed at the value it had when the surface appeared (0 % for a running job) | Fixed: `IslandHosts.accessibilityChanged(on:)`, called when the board redraws (at most every 250 ms) or a toast line changes; tests at the host and through `NotchHUD` | `6af0fd1`, `a9549cc`, `a2562ea` |
| 4 | MEDIUM | A card made key by a click kept the keyboard after it collapsed | Fixed: a move to a smaller surface while keyed resigns key (D-M5a-20); new table state "keyed and leaving" with a row for every event | `b8b6f49` |
| 5 | MEDIUM | An island opened by the menu command or the accessibility action was not held, so a saved result left on its 4 s linger | Fixed, with a narrower rule than suggested: the keyboard counts as a hold, a pin alone does not (D-M5a-19) | `b8b6f49` |
| 6 | MEDIUM | `dragBegan` / `dragEnded` were never sent | Fixed: the thumbnail's drag source reports begin and end through `NotchHUD.dragChanged` to `IslandHosts.dragBegan(on:)` / `dragEnded(on:)` | `a9549cc`, `a2562ea` |
| 7 | HIGH | A request for a display without a host was stored, never shown and never logged; a display added later did not replay it | Fixed: logged, kept, and routed when that display's host is added (D-M5a-22) | `a9549cc` |
| 8 | HIGH | `NotchHUD.display(for:)` invented display 0 when there was none | Fixed: optional; `NotchHUD.canShow`; no item is filed, an error is logged, and the app routes near the drop (D-M5a-23) | `a2562ea` |
| 9 | MEDIUM | With every screen rejected (or none for a moment) the notch route still won and nothing showed | Fixed: a fault line when the reader's list becomes empty, and the default route falls back near the drop while the island cannot show (D-M5a-23) | `924471a`, `a2562ea` |
| 10 | MEDIUM | An empty display list destroyed every host and request, and the board kept items no island drew | Fixed: an empty list changes nothing until a list with a display arrives (D-M5a-22). The suggested re-filing in `NotchHUD.displaysChanged` was not needed once `add()` replays the winner | `a9549cc` |
| 11 | MEDIUM | Same as row 2 (insets, re-measure, captured `goal`) | Fixed with row 2 | `6af0fd1` |
| 12 | MEDIUM | `m5a-exit.sh` ran rows inside `if`, so `set -e` was off and X2 passed when the 50 ms test failed | Fixed: each row runs in its own bash process (D-M5a-24). The suggested `( set -e; run_row … )` was tried in a minimal script first: bash still ignores `set -e` there, and in a background job started inside the `if` | `abf72d0` |
| 13 | MEDIUM | X5 passed when `log show` failed, or when X2–X4 had not run | Fixed: X5 needs X2, X3 and X4 in the same invocation, fails when `log show` fails, prints how many TCC lines it read and warns on an empty stream | `abf72d0` |
| 14 | HIGH | The expansion jumped sideways at its first frame: growing the panel moved the drawn shape with the panel's left edge | Fixed: the chrome holds the shape from the panel's top centre, and a panel resize keeps the shape where it is on screen (D-M5a-21). Found by reading, not seen; the test checks the drawn rectangle on screen before and after the panel grows | `6af0fd1` |
| 15 | MEDIUM | Reduce Motion was ignored between visible surfaces | Fixed: frame, shape and corners change at once, only the content cross-fades; test that a collapse reaches its frame in the same turn | `6af0fd1` |
| 16 | MEDIUM | Content, surface and corners changed outside the animation, so the corners snapped and the cross-fade never ran | Fixed: they now change inside the transition's animation; the spoken text stays outside it. No test can see a transaction; Q24 and Q12 check it | `6af0fd1` |
| 17 | MEDIUM | The expanded card had 10 pt sides against 22 pt corners | Fixed: content at `HUDLayout.contentWidth` (332 pt), 24 pt sides, 14 pt top and bottom, the list too (D-M5a-25) | `401eca5` |
| 18 | MEDIUM | Long names lost the sizes, the reason or the percent to middle truncation of the whole line | Fixed: lines in parts (`LinePart`, `PartedLine`); the name gives way in its middle, the rest stays whole; toast, working line (island and glass card) and list-row titles | `401eca5` |

LOW findings fixed because they were small: the pointer on the screen's top edge counts as inside (LOW 2,
`6af0fd1`); a request filed as another client is logged and the host's hooks are internal (LOW 5, in part,
`6af0fd1`, `a9549cc`); a screen without a number is skipped and duplicate numbers are dropped, and `request` no
longer traps on duplicate ids (LOW 9, `924471a`, `a9549cc`); the demo fixture copy fails loudly (LOW 11,
`abf72d0`); no full stop before the toast's separator (LOW 12, `401eca5`); the Increase Contrast outline is drawn
inside the edge with `strokeBorder` (LOW 14, `6af0fd1`; the top edge is still drawn on notch displays).

### 9.2 Decisions

| ID | Decision | Why |
|---|---|---|
| D-M5a-19 | The keyboard counts as a hold: `isHeld` includes `isKeyed`. A pin without the keyboard does not hold; when the panel gives the keyboard back the full linger starts again. Extends D-N13 | The review suggested `isPinned || isKeyed`. A pin lasts until the pointer passes or Escape, and Escape needs the keyboard, so a pinned card the person had clicked away from would have stayed open with its lingers paused |
| D-M5a-20 | While keyed, any move to a different surface other than `expanded` clears `keyed` and resigns key | design/19 §5.4: the keyboard goes back when the card goes; a tab or a toast should not keep it either |
| D-M5a-21 | `IslandChromeModel.shapeRect` is measured from the panel's top centre (x from the centre line); `setPanelFrame` re-applies the on-screen shape without animation | Every surface hangs from the same centre, so the drawing does not move when the panel grows or shrinks about it, even if SwiftUI merges the two changes of one turn into one frame. The re-application covers frames clamped at a screen edge |
| D-M5a-22 | `IslandHosts` ignores an empty display list, keeps a request for a display it does not know yet, and routes the waiting winner when that display's host is added | Sleep and reconfiguration report no displays for a moment; nothing a client filed should be lost |
| D-M5a-23 | `NotchHUD.display(for:)` is optional and `canShow` says whether the island has a display; `HUDRoute.usable(islandHasDisplay:)` sends a new batch or action near the drop otherwise, a batch is rerouted when its first snapshot arrives (`BatchRoutes.rerouting`), and an action's presenter is chosen when its result arrives, from the route at the drop | No result is filed where nothing draws it |
| D-M5a-24 | Each M5a exit row runs in its own bash process (`--row`, internal) | `set -e` cannot be turned back on inside a conditional |
| D-M5a-25 | The expanded card: 332 pt content, 24 pt sides, 14 pt top and bottom | design/19 §3.4 read as the whole glass card plus 10 pt; the buttons clear the 22 pt corners |
| D-M5a-26 | Display-change streams keep only the newest list | A subscriber needs the current displays, not every list it missed |

### 9.3 Gates (2026-10-23, after `abf72d0`)

Same Mac as §4, Debug app, Photos analysis running (load average 4–9).

| Gate or row | Result | Numbers |
|---|---|---|
| `make test` | pass | 15 test bundles, 1133 tests (1105 before the fixes) |
| `make lint` | pass | swift-format strict, log privacy |
| `make coverage` | pass | lines: ZivletCore 98 %, ZivletTrigger 100 %, ZivletWheelCore 99 %, ZivletEngineKit 97 %, EngineMedia 97 %, EngineImage 95 %, ZivletRuntime 95 %, ZivletTriggerHost 92 %, ZivletWheel 96 %, ZivletActions 91 %, ZivletSettings 96 %, ZivletUI 94 %, ZivletNotchCore 98 %, ZivletNotch 94 % |
| `make app`, `make release-check` | pass | size OK (85 MB installed, 40 MB DMG limits) |
| `make licence-gate` | pass | 13 components, 58 crates |
| `make script-test` | pass | includes the new exit-runner cases |
| X2–X5, X7 (`Scripts/m5a-exit.sh`) | **first run: X2 failed**; second run of X2–X5: pass | First run (load average about 9): `NotchHUDTimingTests` measured 72 ms against the 50 ms budget, and X2 failed. The runner of §4 could not have failed X2 on that step (row 12). Four runs of `make notch-timing` straight after passed, and so did a second run of X2–X5 (load average about 6). X3: `Island: collapsed`, `Island: frame 784 0 232 62`, `Island: toast`, `Island: frame 720 0 360 74`, `Result card: <private> · 1 KB → 4 KB`, and the screenshot shows the toast drawn across the whole frame; X5 read 183 TCC lines with no request for Zivlet; X7 clean |
| X1, X6 | not run again | X1 is the gates above; X6 needs a quiet Mac (O-M5a-2) |

### 9.4 What the tests cover and what they cannot

- New and changed tests: the screen reader (a cancelled watch is dropped, duplicate numbers), the machine table (new
  rows and the keyed-and-leaving state) and hold tests, the host (new geometry, a shrink in flight, the drawn shape
  while the panel grows, Reduce Motion, the spoken text, the top edge), the island shape, the hosts (late display,
  empty list, drags, spoken text), the Notch HUD (no display, spoken progress, the menu command, drags), batch
  routes, the line parts and the card's inset, and the exit runner's script test (a failing step, X5 alone, a
  failing `log show`, a missing fixture).
- Not covered by a test: what SwiftUI draws in each frame (rows 14–16; G-M5a-7); `DragSourceView`'s two session
  callbacks (an `NSDraggingSession` cannot be made in a test; `NotchHUD.dragChanged` and everything after it is
  tested); the app target's wiring of the fallback route (it has no unit tests; `make app` builds it).
- The spoken value follows the board's redraws, which happen on a new percent or step at most every 250 ms; a "time
  left" that changes without a new percent waits for the next redraw.

### 9.5 LOW findings not fixed

| LOW | Finding | Why not now | Next step |
|---|---|---|---|
| 1 | `appear` may never render the housing start state (two changes in one turn) | Unverified; needs drawn frames | G-M5a-7: Q24, then flush the start state if needed |
| 3 | The working card reuses the system indeterminate bar, which animates every frame (D-N7) | Needs a notch-only working view | A stepped bar like `NotchSteps` for the island's working content |
| 4 | `BatchRoutes` never forgets finished batches, and a pending route whose drop made no batch is claimed by the next one | Needs a close callback from both presenters | Forget on close; expire pending routes by their `at` time |
| 5 | `IslandHosts.request(_:from:)` still takes the client twice | The mismatch is now logged; changing the API touches every client | Take only the request, with a separate `withdrawAll` |
| 6 | List rows offer fewer buttons than design/19 §4.3 (no Undo or Copy on a saved row, no Show Details on a failed one) | A design question | O-M5a-4: the full card buttons per row, or the reduced set written into design/19 and Q18 |
| 7 | `theGeneralPaneRendersWithTheNewSection` cannot fail when the section is missing | The section's copy, label and binding have their own tests | Drop the render test or render `PlacementSection` alone |
| 8 | The table has no general "hover intent" and "leaving" states | One leaving state was added (keyed and leaving); `IslandMachineHoverTests` covers the others case by case | Add `.intent` and `.leaving` states with a row per event |
| 10 | `retry` ignores a nil result: the failure is gone, nothing runs, nothing is logged, and the pending route is left for the next drop | Needs the retry to report back before the card closes | Await the result; log and show a toast when it is nil |
| 13 | The island's progress track is about white at 0.1 on black (below 3:1) and the bordered buttons are faint | A style choice for the island | A bar style with the ring's track (`NotchInk.track`) through the environment |

### 9.6 Owner QA rows for the fixes

New rows in [qa/notch.md](qa/notch.md): Q23 (the keyboard goes back when the card goes), Q24 (the card grows evenly
from the housing), Q25 (long names), Q26 (a new display mode under the island). Existing rows that now check a fix:
Q4 (a drag holds the island), Q7 and Q8 (display changes), Q11 (the collapsed value follows progress), Q12 (Reduce
Motion and Increase Contrast), Q18–Q20 (the menu command holds a saved result while the island has the keyboard),
Q22 (sleep and wake keep the board's items).

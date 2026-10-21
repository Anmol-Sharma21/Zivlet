# 12 — M5a implementation plan: NotchIsland core and Notch HUD (TDD)

Date: 2026-10-22. Status: ready to execute after the owner reads it. Design: [design/19-notch](../design/19-notch.md)
(spike P2-197 results, decisions D-N1 … D-N10, states, rules, settings, reuse, M5b fit). This file is the index:
scope, spike summary, task order, decisions, conventions, exit criteria, owner steps and the M5b sketch. The tasks
are in two parts, each under 800 lines:

| Part | Tasks |
|---|---|
| [12a](12a-m5a-notch-core.md) | N0 baseline · N1 modules and `Rect2D` move · N2 display geometry · N3 island layout · N4 island machine · N5 arbiter · N6 placement setting · N7 `ZivletNotch` panel and host |
| [12b](12b-m5a-notch-hud.md) | N8 surface-free HUD content · N9 Notch HUD board · N10 Notch HUD presenter and views · N11 Settings row and app wiring · N12 display geometry in Copy Diagnostics · N13 QA list, exit runner, record |

**Naming.** As asked, this milestone is called **M5a** and the later notch rows **M5b**. [05 §9.2](05-task-list.md)
already uses M5a for the whole of public beta 0.5 and M5b for beta 0.6. In this file and its parts, "M5a" means
NotchIsland core + Notch HUD (P2-115, P2-116, with spike P2-197 done) and "M5b" means the notch Drop Box (P2-141,
P2-55, P2-142, P2-143). Both are slices of 05's beta-0.5 milestone; 05 is not changed. Open point OP-1 (§7) asks the
owner which names to keep.

Clean room: unchanged. No code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch or
shelf app. Every string quoted in these parts is Zivlet's own; new ones are marked *new*.

---

## 0. Verification status of this plan

| Check | Result |
|---|---|
| Baseline | `main` at `1716912`. The gates were **not** re-run for this plan (the Mac was busy, and this change is docs only). The last full run is the M4 record's X1: 13 test bundles, 917 tests, coverage 91–100 % per gated module. Task N0 re-runs `make test lint` before any code changes |
| Spike | Run on this Mac on 2026-10-22, outside the repository (design/19 §1): geometry, panel level, Spaces and full screen, focus, latency, idle CPU, TCC, pill. Not covered: hover with a real pointer, external display, lid closed, Stage Manager, Spaces switching, 16-inch notch, 120 Hz |
| Code read for the plan | `ZivletUI/HUD/*` (`ResultHUD`, `HUDPanel`, `HUDWindow`, `HUDLayout`, `ResultCard`, `ResultCardModel`, `LingerTimer`, `ActionHUD`, `HUDInk`, `HUDCopy`), `ZivletSettings/*`, `ZivletWheelCore/PanelPlacer.swift`, `ZivletWheel/WheelPanel.swift`, `App/ConversionWiring.swift`, `Package.swift`, `Scripts/coverage.sh`, `Scripts/m4-exit.sh`, `Tests/ZivletUITests/HUDFixtures.swift` |
| Code in the parts | Swift in the parts is specification-grade and was **not** compiled for this plan. Each RED step names the expected compile error or assertion, not a recorded one |

---

## 1. Scope

| In M5a | Row | Notes |
|---|---|---|
| Spike | P2-197 (panel half) | Done by the spike: panel above the menu bar in full screen on macOS 27.0, no TCC prompt (design/19 §1). **Still open from P2-197:** drag-near-notch detection (≥ 95 % with 0 accidental opens over 200 recorded normal drags) and the pre-drop-read TCC/iCloud question ([challenge] C4). Both need recorded real drags and move to M5b task NB5 |
| NotchIsland core | P2-115 | `ZivletNotchCore` + `ZivletNotch` (D-N1); geometry, layout, machine, arbiter, panel, host |
| Notch HUD | P2-116 | progress, results, failures, action toasts, "n jobs", Settings choice, migration; today's HUD stays for "Near the drop" |
| Diagnostics | — | display geometry in Copy Diagnostics, to record fixtures (design/19 §3.3) |

Not in M5a: the shelf core, the Drop Box panel, bulk actions, the notch tray and drag proximity (M5b, §9); the picker
at the notch (last phase); any global shortcut; any change to the wheel.

---

## 2. Spike summary (numbers from design/19 §1)

| Measure | Value |
|---|---|
| Notch geometry, 14-inch panel at 1800 × 1169 pt | housing 220 × 38 pt at x 790; `safeAreaInsets.top` 38; menu-bar inset 39 |
| Content inside the housing | hidden by the camera housing, so collapsed content goes in ears (D-N3) |
| Window layers | menu bar 24, island (`.statusBar`) 25, wheel and menus (`.popUpMenu`) 101 |
| Full-screen Space | island visible in the black strip; expanded card over the app |
| Focus | showing and expanding never changed the frontmost app or key window |
| Expand, first frame | cold 35–53 ms; warm 17.2–22.2 ms; settle 402–436 ms (spring); Reduce Motion warm 21–25 ms, settle 207–213 ms |
| Idle CPU | collapsed 0.014 %, expanded 0.007 %, hidden 0.034 %; ring redrawn at 10 Hz 1.65 %; global mouse monitor 0.86 % |
| TCC | no prompt; only `preflight=yes` checks |

---

## 3. Tasks, order and estimate

Order is the dependency order; each task ends green and committed. Sizes are the 05 §1.1 sizes (S ≤ 1 day, M 2–4
days, one engineer, ESTIMATE).

| Task | Title | Module(s) | Depends on | Size | Commit (type, scope) |
|---|---|---|---|---|---|
| N0 | Baseline gates | — | — | S | none |
| N1 | `Rect2D` to `ZivletCore`; empty `ZivletNotchCore`, `ZivletNotch` + test targets + coverage gate | Core, WheelCore, Wheel, Package | N0 | S | `refactor(core)`, `chore(notch)` |
| N2 | `DisplayGeometry`, `NotchGeometry`, recorded fixture | NotchCore | N1 | S | `feat(notch)` |
| N3 | `IslandLayout`: collapsed with ears, toast, expanded, pill, display for a point | NotchCore | N2 | S | `feat(notch)` |
| N4 | `IslandMachine` and `IslandMotion`: surfaces, hover intent and grace, sticky, wheel suppression, Escape, displays | NotchCore | N3 | M | `feat(notch)` |
| N5 | `IslandArbiter`: picker > tray > HUD, hand-back, per display | NotchCore | N4 | S | `feat(notch)` |
| N6 | `HUDPlacement`, `HUDGroup`, store key, migration | Settings | N0 | S | `feat(settings)` |
| N7 | `IslandPanel`, `ScreenGeometryReader`, `IslandHost`, `IslandHosts` | Notch | N5 | M | `feat(notch)` |
| N8 | Surface-free HUD content (`ResultCardContent`, `WorkingContent`, `ActionContent`) | UI | N0 | S | `refactor(ui)` |
| N9 | `NotchHUDBoard` (pure): items, lingers, request, ear copy, announcements, throttle | UI | N5, N8 | M | `feat(ui)` |
| N10 | `NotchHUD` presenter, island views, `HUDPresenter` / `ActionPresenter` | UI | N7, N9 | M | `feat(ui)` |
| N11 | Settings › General row; app wiring (router per drop, wheel suppression, Reduce Motion) | UI, App | N6, N10 | S | `feat(ui)`, `feat(app)` |
| N12 | Display geometry in Copy Diagnostics | UI | N2 | S | `feat(ui)` |
| N13 | `docs/plan/qa/notch.md`, `Scripts/m5a-exit.sh` + test, idle-CPU sampler, exit run, `13-m5a-record.md` | Scripts, docs | all | S | `test(scripts)`, `docs` |

Estimate: about 9 engineer-days (ESTIMATE): 4 M and 10 S tasks. N6, N8 and N12 can run any time after N0. For one
agent in one session, do them in the order above. Stop at the end of a task if the session must end; every task
leaves `main` green.

---

## 4. Decisions

Design decisions D-N1 … D-N10 are in [design/19 §2](../design/19-notch.md). This plan adds:

| ID | Decision | Why |
|---|---|---|
| D-M5a-1 | `Rect2D` moves from `ZivletWheelCore` to `ZivletCore/Shared` (with `Point2D`) | The notch core must not depend on the wheel core; four files use `Rect2D` |
| D-M5a-2 | The placement is resolved **at the drop** by a pure `PresenterRouter` (`ZivletUI`); a change applies to the next job or action only | Moving live items between the card and the island adds states for no user value |
| D-M5a-3 | Action toasts and action cards follow the same placement as conversions | The owner listed "action toasts (Copied, Moved + Undo) too" |
| D-M5a-4 | VoiceOver focus on the island expands it, as hover does; the collapsed island's accessibility value is its full text | VoiceOver users must not need hover (design/19 §5.5) |
| D-M5a-5 | The TCC exit check counts tccd requests with `preflight=no` attributed to Zivlet; `preflight=yes` checks (AppKit's launch-time Input Monitoring preflight, WindowServer's screen-capture preflight during screenshots) are listed but do not fail the row | Spike S11: these preflights happen for any AppKit process and never prompt |
| D-M5a-6 | The app tells the island when the wheel shows and hides (`wheelShown` / `wheelHidden`) from the existing wheel wiring; the island never inspects the wheel | Keeps the notch modules free of wheel types (W-8) |
| D-M5a-7 | No `dropTarget` surface, tray client or proximity detector in M5a; the client enum already has `.tray` and `.picker` and the arbiter is tested with fakes for both | YAGNI for behaviour, but the seams M5b needs are tested now (design/19 §8) |

---

## 5. Conventions

| Item | Rule |
|---|---|
| Environment | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before every `swift`, `xcodebuild`, `make`. On a busy Mac prefix heavy commands with `nice -n 10`. No `make vendor` clean rebuild, full matrix or benchmark is needed for M5a |
| TDD | Each task: write the failing test → run it and see the stated failure → implement the minimum → green → refactor → commit. Refactor tasks (N1's move, N8) keep the existing tests green before and after instead |
| Gates after every task | `make test lint`; `make coverage` when a gated module changed (`ZivletNotchCore`, `ZivletNotch`, `ZivletUI`, `ZivletSettings`, `ZivletCore`, `ZivletWheelCore`, `ZivletWheel`); `make app` after N1, N10, N11 |
| Full gate list (M5a exit) | `make test`, `make lint`, `make coverage` (80 % per module; 15 modules after N1), `make app`, `make release-check`, `make licence-gate` |
| Commits | Conventional, `git commit -s`, no `Co-Authored-By`; scopes `core`, `notch`, `settings`, `ui`, `app`, `scripts`, `docs` |
| Code rules | Immutable values (copies via `with` or new values), files < 800 lines (aim 200–400), functions < 50 lines, nesting ≤ 4, no `print`, typed errors with Zivlet's own copy, validation at boundaries (stored settings, display values from AppKit) |
| Tests | Swift Testing (`@Suite`, `@Test`, `#expect`), as in the existing bundles. Shell tests keep displays off screen (x −5000) like `HUDTimingTests` |
| Launching the app | Quit any Zivlet you launch with `osascript -e 'quit app "Zivlet"'` |
| Public repo | No personal paths, scratch paths or private working notes in code, docs or commit messages |
| Push | Never; the owner reviews and pushes |

---

## 6. Exit criteria (run by `Scripts/m5a-exit.sh`, task N13)

| Row | Check | Pass when |
|---|---|---|
| X1 | `make test lint coverage app release-check licence-gate` | all pass; `ZivletNotchCore` and `ZivletNotch` ≥ 80 % line coverage; no other gated module drops below 80 % |
| X2 | Drop → island budget | `NotchHUDTimingTests.aDropShowsTheIslandWithin50ms` passes (part of X1), and the signpost `drop→island` appears in the demo log |
| X3 | Debug-app demo with the notch placement | `make notch-demo` converts the demo HEIC to JPEG with `-ZivletHUDPlacement notch`; the log shows `Island: collapsed`, `Island: toast` and the result line; a screenshot of the island region is saved in `build/m5a-exit/` |
| X4 | Debug-app demo with "Near the drop" | the same demo with `-ZivletHUDPlacement nearDrop` shows today's card (log line `Result card: …`), no island |
| X5 | No TCC prompt | no tccd request with `preflight=no` attributed to Zivlet while X3 and X4 ran (D-M5a-5) |
| X6 | Idle CPU of the Debug app | island hidden: ≤ 0.1 % over 20 s; collapsed with no progress change: ≤ 0.1 %; collapsed with progress at 10 Hz: ≤ 1 % (`Scripts/idle-cpu.sh`) |
| X7 | Hygiene | every M5a commit signed off, none with `Co-Authored-By`; no changed source file ≥ 800 lines; no personal path in the diff |

M5a is **code complete** when X1–X7 pass. It is **complete** when the owner rows in `docs/plan/qa/notch.md`
(design/19 §10, Q1–Q17) are run; the record says which are open.

---

## 7. Owner steps and open points

| ID | Item | Recommendation |
|---|---|---|
| OP-1 | Milestone names: this plan's M5a and M5b collide with 05 §9.2's M5a (beta 0.5) and M5b (beta 0.6) | Keep "M5a"/"M5b" for the notch slices as asked and rename 05's beta milestones to "B0.5", "B0.6", "B0.7" in a later docs change; or call these "M5a-notch-1/2". The owner picks |
| OP-2 | OWN-HUD-2: the label and behaviour of the second placement ("Bottom-right corner" in the owner's words; today's card opens near the drop) | Ship "Near the drop" (today's behaviour) unless the owner wants a fixed bottom-right corner; either is a small change (design/19 §6) |
| OP-3 | Hover intent delay (150 ms) and grace (300 ms) | Keep until Q1 on real hardware says otherwise |
| OP-4 | Owner QA rows Q1–Q17 | Run with `docs/plan/qa/notch.md` after X1–X7 pass |
| OP-5 | More display fixtures (16-inch, other scaled modes) | Copy Diagnostics on those Macs (N12, Q15); the values become recorded fixtures |

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| SwiftUI layout of the expanded content makes the first expand slow (spike: 35–53 ms cold) | D-N9 pre-warm; X2 and the host test measure it |
| Extracting the HUD content (N8) changes today's card | refactor under the existing `ResultCardTests`, `HUDTests`, `ActionHUDTests`; `make convert-demo` before and after |
| The board duplicates `ResultHUD` logic | the board reuses `ResultCardModel`, `LingerTimer`, `CardState` and the same press closures; review checks for copies |
| Tests that need a window server are flaky on CI | shell tests stay in `ZivletNotchTests`/`ZivletUITests` with off-screen displays, as M4's HUD tests already do; pure logic carries the coverage |
| Hover feel unknown until Q1 | timings are constants in `IslandMachine.Timing`; Q1 tunes them without code changes elsewhere |
| The session ends mid-plan | every task is a green, committed step; N13 records what is done |

---

## 9. M5b sketch: the notch Drop Box (not planned in detail yet)

Order per OWN-PLAN-3: shelf core → Drop Box panel → bulk actions → notch tray. Each row keeps its 05 acceptance
(§9.1 P2-55, §9.5 P2-141, P2-142, P2-143). What each needs from M5a is in design/19 §8.

| Task | Row | Module(s) | Uses from M5a | Size |
|---|---|---|---|---|
| NB1 | P2-141 shelf core: `Shelf`, `ShelfItem`, bookmarks, `boxes.json`, owned copies, auto-clear plans | `ZivletShelfCore` (new, pure) | `Rect2D` in `ZivletCore` (dock frames) | M |
| NB2 | P2-141 shake detector (opt-in) on recorded traces | `ZivletTrigger` | — | S |
| NB3 | P2-55 Drop Box panel (states, dock, grid/list, Quick Look, keyboard, accessibility), replaces Float | `ZivletActions` | the `HUDWindow`/`IslandPanel` key rules (D-M4-16) | L |
| NB4 | P2-142 bulk actions (Share, AirDrop, Copy, Move/Copy to, Convert all; Zip after P2-111) | `ZivletActions`, `ZivletUI` | `ActionPresenter` toasts at the notch (D-M5a-3) | M |
| NB5 | P2-197 remainder: record 200 normal drags and 50 notch-bound drags on real hardware; pure `NotchProximity` with thresholds that reach ≥ 95 % detection and 0 accidental opens; settle the pre-drop-read TCC/iCloud question ([challenge] C4) | `ZivletTrigger`, owner recordings | `NotchGeometry`, `IslandLayout.display(for:in:)` | M |
| NB6 | Tray client: `.tray` requests, a `dropTarget` resting surface, drag registration only while it asks, wheel wins | `ZivletActions`, `ZivletNotch`, `ZivletNotchCore` | arbiter priority, host, motion, `wheelShown` | M |
| NB7 | Tray drop → current box; compact box view as the tray's expanded content; full panel one click away | `ZivletActions` | host surfaces per client | M |
| NB8 | M5b QA (tray rows of P2-143, Drop Box rows) and exit runner | docs, Scripts | `m5a-exit.sh` pattern | S |

Picker at the notch (last phase): a `.picker` client in `ZivletWheel` that draws the Bar or Wheel picker as the
island's expanded content during a drag-pick and raises its host's level while it shows (design/19 §8).

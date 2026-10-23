# 14 — Notch design pass: implementation plan (TDD)

Date: 2026-10-24. Status: ready to execute after the owner reads it; nothing in it is built. Design:
[design/19b-notch-look](../design/19b-notch-look.md) (audit, decisions D-NL1 … D-NL13, tokens, probe results, copy per
state, the CPU change). Owner decision: OWN-UI-1 in [00-decisions](../design/00-decisions.md). Base: the M5a code
([13-m5a-record](13-m5a-record.md)), on the local branch `notch-design` made from `main` at `0b5a5e6`.

Clean room: unchanged. No code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch or
shelf app. New strings are marked *new* and are Zivlet's own.

---

## 0. Verification status of this plan

| Check | Result |
|---|---|
| Gates | **Not run** for this plan (docs only, and the Mac was busy with photo analysis). Task D0 runs them before any code change. The last full run is M5a's X1 at `77927bc` (15 test bundles, 1105 tests) |
| Probe | Run on 2026-10-24 outside the repository (19b §4): APIs, blend, contrast by backdrop and size, appearance, animating shape, opacity, CPU of still glass |
| Profile | One Debug run of `-ZivletIslandPreview progress` on 2026-10-24: 1.03 % over 30 s (no baseline in that run) and a 20 s `sample` (19b §6.1) |
| Code read | `ZivletNotch/*` (chrome, shape, host, host events, animation, panel), `ZivletUI/Notch/*` (board, derived, item, copy, presenter, actions, tab, toast, card, list, glyphs, ink, preview), `ZivletUI/HUD` content views and `HUDInk`, `App/AppDelegate+Demo.swift`, `Scripts/notch-idle.sh`, `Scripts/idle-cpu.sh`, `Scripts/check-release-paths.sh`, `Makefile` |
| Not seen | V2, V4, V7–V14 of 19b §1.1 were read from code, not seen on screen |

---

## 1. Scope

In: the look of every island surface (19b §1.1), Liquid Glass below the housing, the shape's flare, tokens, icon
buttons, the Reduce Transparency and Increase Contrast finishes, content motion, the G-M5a-1 CPU change, Release-build
measurement, demo screenshots of every state, the QA list and a record.

Out: island rules (machine, arbiter, holds, timings, frames), the "Near the drop" HUD's look (it keeps M4's glass card;
OWN-UI-1 is about the notch), M5b, new Settings. If a task finds it needs a rule change, it stops and asks.

---

## 2. Decisions added by this plan

| ID | Decision | Why |
|---|---|---|
| D-ND1 | The island gets its own content views (`NotchWorkingCard`, `NotchResultCard`, `NotchFailureCard`, `NotchActionCard`); they use the same models (`BatchSnapshot`, `ResultCardModel`, `CardState`, `ActionHUDModel`) and closures. `WorkingContent`, `ResultCardContent` and `ActionContent` stay as they are for the card near the drop | 19b changes the island's layout and buttons, not the M4 card's. Shared models keep copy and button rules in one place (design/19 §7) |
| D-ND2 | Surface finish is a pure value `IslandFinish` in `ZivletNotchCore`, resolved from surface, notch or pill, Reduce Transparency and Increase Contrast | Testable without a window server (R1); the chrome only draws it |
| D-ND3 | The island preview compiles when `DEBUG` **or** `ZIVLET_ISLAND_PREVIEW` is set. Only `make notch-idle CONFIG=release` sets the second one, into its own derived-data folder; `make release-check` fails if the shipped binary contains `-ZivletIslandPreview` | G-M5a-1 asks for an optimised measurement; shipped builds must never show made-up jobs |
| D-ND4 | Screenshot-only DEBUG flags: `-ZivletIslandFinish glass|solid|contrast` (forces the finish without touching the owner's accessibility settings), `-ZivletIslandPill YES` (treats every display as having no notch), `-ZivletIslandBackdrop white|black` (a plain panel under the island for contrast readings) | Every state must be captured for the owner (OWN-UI-1), and the real settings are the owner's |

---

## 3. Conventions

| Item | Rule |
|---|---|
| Environment | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before every `swift`, `xcodebuild`, `make`; `nice -n 10` in front of heavy commands; long timeouts or background runs; never `make vendor` |
| Branch | All work on `notch-design`. Never commit to `main`, never push, never rewrite `main` |
| TDD | Each task: write the failing test, run it and see the named failure, implement the minimum, green, refactor, commit. One commit per task unless a task says otherwise |
| Gates after every task | `make test lint`; `make coverage` when a gated module changed; `make app` after D9, D13–D17 and D18 |
| Full gates (exit) | `make test`, `make lint`, `make coverage` (80 % per module, 14 modules), `make app`, `make release-check`, `make licence-gate`, `make script-test`, `Scripts/m5a-exit.sh` rows, `make notch-idle` (Debug) and `make notch-idle CONFIG=release` |
| Commits | Conventional, `git commit -s`, no `Co-Authored-By`; scopes `notch`, `ui`, `app`, `scripts`, `docs` |
| Code rules | Immutable values, files < 800 lines (aim 200–400), functions < 50 lines, nesting ≤ 4, no `print`, explicit typed errors, validation at boundaries |
| Tests | Swift Testing as in the existing bundles; shell tests keep displays at x −5000. No test asserts glass pixels (19b §7) |
| Launching the app | Quit any Zivlet you launch: `osascript -e 'quit app "Zivlet"'` |
| Public repo | No personal paths, scratch paths or private notes in code, docs or commit messages; records say what was not measured |

Test command for one suite: `cd Packages/ZivletKit && swift test --filter <SuiteType>` (after `source Scripts/env.sh`).

---

## 4. Task order

| Phase | Tasks |
|---|---|
| Measure first | D0 baseline · D1 Release-measurable preview |
| CPU (G-M5a-1) | D2 visible key and quanta · D3 gate in `show` · D4 chrome accessibility split · D5 measure Debug and Release |
| Surfaces | D6 `IslandFinish` · D7 content tokens and contrast · D8 shape flare and radii · D9 chrome draws finishes |
| Content | D10 icon button · D11 tab · D12 toast · D13 working card · D14 result card · D15 failure and action cards · D16 list rows · D17 content motion |
| Evidence | D18 demo states, screenshots and contrast check · D19 QA list and cross-references · D20 exit run and record |

The CPU work comes before the look so that D5's numbers compare M5a's views with and without the fix, and the look's
own cost shows separately in D20.

---

## Task D0 — Baseline

1. `git switch notch-design` (it exists after this plan's commit); `git status` clean.
2. `export DEVELOPER_DIR=…; nice -n 10 make test lint` → record test count and time in the task's notes for D20.
3. `nice -n 10 make app` then `make notch-idle` (Debug, 120 s per state) → keep the five numbers as "before" for D5.
   If the load average is above 4 at the start, write it down next to the numbers.

No commit.

---

## Task D1 — Release-measurable island preview (D-ND3)

Files: `Packages/ZivletKit/Sources/ZivletUI/Notch/IslandPreview.swift`, `App/AppDelegate+Demo.swift`,
`Scripts/notch-idle.sh`, `Scripts/check-release-paths.sh`, `Scripts/tests/test-notch-idle.sh` (new or extended),
`Makefile`.

### D1.1 Failing tests first

```bash
# Scripts/tests/test-notch-idle.sh
test_release_config_builds_its_own_app() {   # CONFIG=release → derived data build/NotchIdleRelease, Release products
  out=$(ZIVLET_IDLE_DRY_RUN=1 CONFIG=release Scripts/notch-idle.sh)
  assert_contains "$out" "build/NotchIdleRelease/Build/Products/Release/Zivlet.app"
  assert_contains "$out" "SWIFT_ACTIVE_COMPILATION_CONDITIONS=ZIVLET_ISLAND_PREVIEW"
}
test_unknown_config_is_refused() { CONFIG=profile Scripts/notch-idle.sh; assert_exit 2; }
test_release_check_rejects_a_binary_with_the_preview_flag() {   # a fixture Mach-O with the string
  assert_exit 1 Scripts/check-release-paths.sh --scan-only "$FIXTURE_WITH_PREVIEW_FLAG"
}
```

Run `make script-test` → the three tests fail (no `CONFIG`, no `--scan-only`).

### D1.2 Implement

- `IslandPreview.swift` and the preview branch in `AppDelegate+Demo.swift`: `#if DEBUG || ZIVLET_ISLAND_PREVIEW`.
  Only the preview's launch-argument path is opened up; the other demo flags stay `#if DEBUG`.
- `notch-idle.sh`: `CONFIG=debug|release` (default debug). Release: `xcodebuild … -configuration Release
  -derivedDataPath build/NotchIdleRelease CODE_SIGN_IDENTITY=- SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited)
  ZIVLET_ISLAND_PREVIEW' build` under `nice -n 10`, then the same states. `ZIVLET_IDLE_DRY_RUN=1` prints the plan and
  exits (for the script test). The output names the configuration on every line.
- `check-release-paths.sh`: after the Homebrew scan, `strings -a` of the app binary must not contain
  `-ZivletIslandPreview`; `--scan-only <file>` runs only the scans on a given file (for the test).
- `Makefile`: `notch-idle: $(ENV) CONFIG=$${CONFIG:-debug} Scripts/notch-idle.sh`.

Verify: `make script-test`; `nice -n 10 make release-check` (the shipped binary has no preview flag).
Commit: `chore(scripts): measure the island's idle CPU on an optimised build too`

---

## Task D2 — Visible key and progress quanta (pure; 19b §6.2)

Files: new `Packages/ZivletKit/Sources/ZivletUI/Notch/NotchVisible.swift`; new
`Packages/ZivletKit/Tests/ZivletUITests/NotchVisibleTests.swift`.

### D2.1 Failing tests first

```swift
@Suite("Visible progress and the visible key (G-M5a-1, 19b §6.2)")
struct NotchVisibleTests {
    @Test func quantaFollowTheDrawnLengthInPixels() {
        #expect(VisibleProgress.steps(lengthInPoints: 50, scale: 2) == 100)  // ring at 2×
        #expect(VisibleProgress.steps(lengthInPoints: 50, scale: 1) == 50)   // ring on a 1× display
        #expect(VisibleProgress.steps(lengthInPoints: 10, scale: 2) == 20)
    }
    @Test func aChangeSmallerThanOneStepIsNotAChange() {
        #expect(VisibleProgress(0.401, steps: 100) == VisibleProgress(0.409, steps: 100))
        #expect(VisibleProgress(0.401, steps: 100) != VisibleProgress(0.411, steps: 100))
        #expect(VisibleProgress(1.2, steps: 100).step == 100 && VisibleProgress(-1, steps: 100).step == 0)
    }
    @Test func snapshotsThatDrawTheSameHaveTheSameKey() throws {
        let a = try HUDFx.running(JobProgress(fraction: 0.402, eta: .seconds(40)))
        let b = a.applyingProgress(JobProgress(fraction: 0.404, eta: .seconds(38)))  // same % and same "< 1 min"
        #expect(VisibleKey(a, ringSteps: 100, barSteps: 100) == VisibleKey(b, ringSteps: 100, barSteps: 100))
    }
    @Test func aNewPercentANewTimeLeftOrANewFileChangesTheKey() { /* 0.41; eta 90 s ("2 min"); next item → differ */ }
    @Test func finishingAlwaysChangesTheKey() { /* running 0.999 vs finished → differ; failed vs saved → differ */ }
}
```

`HUDFx` is the existing fixture helper (`running` makes `clip.mov` → MP4); add a test-support extension
`BatchSnapshot.applyingProgress(_:)` next to it (it applies `.changed(…, .running(progress))` to the first item).
Run `swift test --filter NotchVisibleTests` → fails to compile (`VisibleProgress`, `VisibleKey` missing).

### D2.2 Implement

`VisibleProgress` (`step`, `steps`; `init(_ fraction: Double?, steps:)`, clamped; nil for unknown length) and
`VisibleKey` (equatable value: per item kind and status, current item name, ring and bar `VisibleProgress`, stepped
glyph step, `HUDCopy.timeLeft` long form and the new short form from D13 — until D13 lands, the long form alone —
output count, failure count, finished). No clock, no AppKit.

Commit: `feat(ui): the island knows when a snapshot draws nothing new`

---

## Task D3 — Stop unchanged snapshots in `NotchHUD.show` (19b §6.2)

Files: `Packages/ZivletKit/Sources/ZivletUI/Notch/NotchHUD.swift`, `NotchHUDBoard.swift` (store the last key per item),
`Packages/ZivletKit/Tests/ZivletUITests/NotchHUDTests.swift`.

### D3.1 Failing tests first

```swift
@Test func snapshotsThatDrawNothingNewNeitherPublishNorReachTheHost() async throws {
    let rig = try NotchRig.notch()                                 // existing rig: off-screen hosts, manual clock
    var transitions = 0
    rig.hud.onApply = { transitions += 1 }                         // new test seam on every `apply`
    let first = try HUDFx.running(JobProgress(fraction: 0.40, eta: .seconds(40)))
    rig.hud.prepare(near: NotchRig.onNotch); rig.hud.show(first)
    let before = transitions
    for step in 1...4 { rig.hud.show(first.applyingProgress(JobProgress(fraction: 0.40 + Double(step) * 0.001, eta: .seconds(40)))) }
    #expect(transitions == before)
}
@Test func theNextVisibleStepStillRedrawsWithin250ms() { /* 0.41 after ≥ 250 ms → one publish, one accessibilityChanged */ }
@Test func aFinishedSnapshotIsNeverDropped() { /* identical progress but finished → toast request filed */ }
```

`onApply` is an internal closure on `NotchHUD` called at the top of `apply` (default empty), like the existing
`announce` seam. Run → the first test fails: four extra transitions.

### D3.2 Implement

In `show`, after finding `known`: compute `VisibleKey` with the ring's and bar's steps (from D7's tokens; until then
100 and 100) and return when it equals the item's stored key and the snapshot is not finished. Store the key in the
board item on every applied snapshot. Keep the drop-interval signpost behaviour (a first snapshot always passes).

Commit: `perf(ui): a snapshot that draws nothing new stops before the board`

---

## Task D4 — The chrome stops reading the spoken value (19b §6.2)

Files: `Packages/ZivletKit/Sources/ZivletNotch/IslandChrome.swift`, new `IslandAccessibility.swift`,
`IslandHost+Events.swift` (`refreshAccessibility`), `Packages/ZivletKit/Tests/ZivletNotchTests/IslandHostTests.swift`.

### D4.1 Failing test first

```swift
@Test func aNewSpokenValueDoesNotInvalidateTheChrome() throws {
    let client = FakeClient()                                     // existing fake: value "3 lines"
    let host = makeHost(try OffscreenDisplays.notch(), client: client)
    host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
    var invalidated = false
    withObservationTracking {
        _ = host.chrome.shapeRect; _ = host.chrome.content; _ = host.chrome.surface; _ = host.chrome.opacity
        _ = host.chrome.topRadius; _ = host.chrome.bottomRadius; _ = host.chrome.finish
    } onChange: { invalidated = true }
    client.lines = 5
    host.refreshAccessibility()
    #expect(!invalidated && host.accessibility.value == "5 lines")
}
```

Run → fails to compile (`host.accessibility`, `chrome.finish` missing; `finish` arrives in D9 — until then drop that
line from the tracking block and add it back in D9).

### D4.2 Implement

`IslandAccessibilityModel` (`@Observable`: label, value, action name, action and focus callbacks) owned by the host;
`IslandAccessibility: ViewModifier` reads only that model and applies `.accessibilityElement(children: .contain)`,
label, value, action and focus. `IslandChrome` applies the modifier and no longer reads those properties. Move the
existing accessibility tests to `host.accessibility`.

Commit: `perf(notch): the spoken value updates without redrawing the island`

---

## Task D5 — Measure G-M5a-1 on Debug and Release

1. `nice -n 10 make app`; `make notch-idle` → "after" numbers for the Debug app.
2. `make notch-idle CONFIG=release` → before-look Release numbers.
3. A 20 s `sample` of the progress state on each build; compare the main thread's busy samples with 19b §6.1.
4. If progress is still over 1 % on either build and AppKit's window layout pass is still a large share: set
   `measurer.sizingOptions = []`, give the tab a fixed frame inside the chrome, re-measure, keep the change only if it
   helps (test first: a host test that the measurer's and hosting view's `sizingOptions` are empty).

Commit only if step 4 changed code: `perf(notch): the island's hosting views skip AppKit layout`. The numbers go to
the record (D20) with load average and build configuration.

---

## Task D6 — `IslandFinish` (pure; D-NL1, D-NL3, D-ND2)

Files: new `Packages/ZivletKit/Sources/ZivletNotchCore/IslandFinish.swift`; new
`Packages/ZivletKit/Tests/ZivletNotchCoreTests/IslandFinishTests.swift`.

### D6.1 Failing tests first

```swift
@Suite("Island finish (OWN-UI-1, 19b D-NL1, D-NL3)")
struct IslandFinishTests {
    @Test(arguments: [
        (IslandSurface.collapsed, true, false, false, IslandFinish.black),
        (.toast, true, false, false, .glass(band: 38)),
        (.expanded, true, false, false, .glass(band: 38)),
        (.collapsed, false, false, false, .glass(band: 0)),       // pill
        (.toast, true, true, false, .solid(band: 38, outline: false)),
        (.expanded, true, false, true, .solid(band: 38, outline: true)),
        (.collapsed, true, false, true, .black),                  // the tab stays black; outline from `outlined`
        (.collapsed, false, true, false, .solid(band: 0, outline: false)),
    ])
    func finishFollowsSurfaceDisplayAndSettings(
        surface: IslandSurface, notch: Bool, reduceTransparency: Bool, increaseContrast: Bool, expected: IslandFinish
    ) throws {
        let display = try notch ? DisplayFixtures.mbp14MoreSpace() : DisplayFixtures.noNotch1080()
        #expect(IslandFinish.resolve(surface, on: display, reduceTransparency: reduceTransparency,
                                     increaseContrast: increaseContrast) == expected)
    }
    @Test func increaseContrastOutlinesEveryFinish() { /* outlined == increaseContrast for black, glass, solid */ }
    @Test func hiddenKeepsTheLastFinish() { /* resolve(.hidden, …, previous: f) == f */ }
}
```

Run → fails to compile.

### D6.2 Implement

`public enum IslandFinish: Sendable, Equatable { case black, glass(band: Double), solid(band: Double, outline: Bool) }`
plus `outlined`; `band` = `NotchGeometry.housing(of:)?.height ?? 0`. Pure, nonisolated.

Commit: `feat(notch): the island picks black, glass or solid per surface and setting`

---

## Task D7 — Content tokens and contrast (D-NL5 … D-NL7, D-NL11; 19b §3)

Files: new `Packages/ZivletKit/Sources/ZivletNotch/IslandLook.swift` (scrim, fade, flare, radii, outline, solid grey,
worst glass luminance), new `Packages/ZivletKit/Sources/ZivletUI/Notch/NotchLook.swift` (spacing, type, symbol sizes,
ring, bar, button), `ZivletUI/Notch/NotchInk.swift` (track 0.3; contrast over a surface luminance),
`Packages/ZivletKit/Tests/ZivletUITests/NotchInkTests.swift`, new `NotchLookTests.swift`.

### D7.1 Failing tests first

```swift
@Suite("Island ink on glass, solid and black (19b §3.5)")
struct NotchInkTests {
    let worst = IslandLook.worstGlassLuminance          // 0.12: measured 0.102 plus margin (19b §4.2 P7)
    @Test func textOnTheWorstGlassPasses() {
        #expect(NotchInk.contrast(textOpacity: 1, over: worst) >= 6)
        #expect(NotchInk.contrast(textOpacity: NotchInk.secondaryOpacity, over: worst) >= 4.5)
    }
    @Test func progressMeetsNonTextContrastOnTheWorstGlass() {
        #expect(NotchInk.contrast(fillOver: worst) >= 3)
        #expect(NotchInk.contrast(fill: 1, track: NotchInk.trackOpacity, over: worst) >= 3)
    }
    @Test func theSolidFallbackPassesWithMargin() { /* grey 0.11: white ≥ 16, secondary ≥ 11 */ }
    @Test func blackStillPasses() { /* as M5a: white > 20, secondary ≥ 4.5, ring ≥ 3 */ }
}
@Suite("Island tokens (19b §3)")
struct NotchLookTests {
    @Test func spacingIsOnTheFourPointGrid() { /* every NotchLook.Spacing value % 4 == 0 */ }
    @Test func innerRadiiAreConcentric() { #expect(IslandLook.Radius.inner == IslandLook.Radius.card - NotchLook.Spacing.l) }
    @Test func theScrimIsTheMeasuredOne() { #expect(IslandLook.scrim == 0.5) }
}
```

Run → fails to compile.

### D7.2 Implement

The token enums with the 19b §3 values; `NotchInk` gains `contrast(textOpacity:over:)`, `contrast(fillOver:)`,
`contrast(fill:track:over:)` (sRGB compositing as `HUDInk.worstContrast` does) and `trackOpacity = 0.3`. Existing
views keep compiling (the old names stay until D11–D16 move to the tokens, then go).

Commit: `feat(ui): one set of tokens for the island's spacing, type, radii and ink`

---

## Task D8 — Shape flare and radii (D-NL4, D-NL5)

Files: `Packages/ZivletKit/Sources/ZivletNotch/IslandShape.swift`, `IslandHost+Events.swift` (`radius(_:)`),
`ZivletNotchCore/IslandLayout.swift` (`Metrics.toastRadius = 18`, `expandedRadius = 24`),
`Packages/ZivletKit/Tests/ZivletNotchTests/IslandShapeTests.swift`, `IslandHostLayoutTests.swift`,
`ZivletNotchCoreTests/IslandLayoutTests.swift`.

### D8.1 Failing tests first

```swift
@Test func theTopEdgeSpansTheFrameAndTheBodyIsInsetByTheFlare() {
    let rect = CGRect(x: 0, y: 0, width: 232, height: 62)
    let path = IslandShape(top: 0, bottom: 12, flare: 6).path(in: rect)
    #expect(path.contains(CGPoint(x: 0.5, y: 0.2)) && path.contains(CGPoint(x: 231.5, y: 0.2)))   // top corners
    #expect(!path.contains(CGPoint(x: 1, y: 20)) && path.contains(CGPoint(x: 7, y: 20)))          // body inset 6
    #expect(path.boundingRect.width == 232)
}
@Test func thePillHasNoFlare() { /* flare 0, top radius = height / 2: (0.5, 0.5) outside, symmetric */ }
@Test func theFlareAnimatesWithTheRadii() { /* animatableData carries (top, bottom, flare) */ }
@Test func theOutlineInsetKeepsTheFlareConcentric() { /* inset(by: 0.5): flare shrinks by 0.5 */ }
// IslandHostLayoutTests: toast bottom radius 18, expanded 24, collapsed 12; pill none flared
// IslandLayoutTests: unchanged frames; the collapsed island still covers ≤ 6 pt beside the housing (D-N3)
```

Run → fails (`flare` parameter missing; radii 12/22).

### D8.2 Implement

Add `flare` (animatable) to `IslandShape`: the path starts at the frame's top corners, curves inward with a concave
quarter circle of radius `flare` to the body's side, runs down, and closes with the continuous bottom corners of the
body (`UnevenRoundedRectangle` for the body plus two concave corner wedges). `IslandHost.applyShapeStyle` sets flare
6 on notch displays, 0 on the pill; radii from `IslandLayout.Metrics`.

Commit: `feat(notch): the island flares into the screen edge and its corners follow the card`

---

## Task D9 — The chrome draws the finish (D-NL1 … D-NL3)

Files: `Packages/ZivletKit/Sources/ZivletNotch/IslandChrome.swift`, `IslandHost.swift`, `IslandHost+Events.swift`,
`IslandHosts.swift` (display-option changes), `IslandPanel.swift` (`appearance = darkAqua`), new
`IslandFinishView.swift`, tests in `ZivletNotchTests/IslandHostLayoutTests.swift`, `IslandPanelTests.swift`,
`IslandHostsTests.swift`.

### D9.1 Failing tests first

```swift
@Test func theHostSetsTheFinishPerSurface() async throws {      // fake display options: RT off, IC off
    let host = makeHost(try OffscreenDisplays.notch(), client: FakeClient(), options: FakeDisplayOptions())
    host.apply([.show(.collapsed, display: 1, contentHeight: 0)]);  #expect(host.chrome.finish == .black)
    host.apply([.show(.toast, display: 1, contentHeight: 0)]);      #expect(host.chrome.finish == .glass(band: 38))
}
@Test func reduceTransparencyTurnsGlassSolidAtTheNextSurface() { /* options.rt = true; post change → .solid(38, false) */ }
@Test func increaseContrastAddsTheOutline() { /* .solid(38, true); chrome.outlined */ }
@Test func thePanelIsAlwaysDark() { #expect(IslandPanel().appearance?.name == .darkAqua) }
@Test func aForcedFinishWinsInDebug() { /* IslandHosts(finishOverride: .solid) → every surface solid (D-ND4) */ }
```

`makeHost` gains an `options:` parameter and `FakeDisplayOptions` is new test support. The host reads display
options through a protocol `DisplayOptions` (`reduceTransparency`, `increaseContrast`,
`changes` stream); the app passes an `NSWorkspace` adapter, tests a fake. Run → fails to compile.

### D9.2 Implement

`IslandFinishView` draws, inside the clip: `.black` → black; `.glass(band)` → the band gradient (black to
`band`, transparent `IslandLook.fade` lower) over a black scrim at `IslandLook.scrim`, all under
`.glassEffect(.regular, in: shape)`; `.solid(band, outline)` → the band gradient over grey 0.11; the outline from
`finish.outlined` replaces the M5a `colorSchemeContrast` check. `IslandPanel.init` sets `appearance`.
`IslandHosts` subscribes to `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` through the adapter and
tells each host, which re-resolves at its next surface change.

Verify: `make test lint coverage`, `nice -n 10 make app`, then
`open -n build/DerivedData/Build/Products/Debug/Zivlet.app --args -ZivletHUDPlacement notch -ZivletIslandPreview result`
and a look at the toast and card (screenshot kept for D18; quit the app).
Commit: `feat(notch): toasts and cards below the housing are Liquid Glass, black at the top edge`

---

## Task D10 — Icon button (D-NL9)

Files: new `Packages/ZivletKit/Sources/ZivletUI/Notch/NotchIconButton.swift`; new
`Packages/ZivletKit/Tests/ZivletUITests/NotchIconButtonTests.swift`.

### D10.1 Failing tests first

```swift
@Suite("Island icon buttons (19b D-NL9)")
struct NotchIconButtonTests {
    @Test(arguments: NotchHUD.Press.allCases)
    func everyPressHasASymbolAndTodaysTitle(press: NotchHUD.Press) {
        #expect(!NotchIconButton.symbol(press).isEmpty)
        #expect(NotchIconButton.title(press) == NotchListRow.title(press))   // the M5a words, unchanged
    }
    @Test func theHitAreaIs28Points() throws { /* ImageRenderer of the button: 28 × 28 */ }
    @Test func theLabelAndTooltipAreTheTitle() { /* accessibility label via the view's AX tree in an NSHostingView */ }
    @Test func increaseContrastShowsTheBackgroundAtRest() { /* NotchIconButton.restingFill(increaseContrast:) 0 / 0.18 */ }
}
```

`NotchHUD.Press` gains `CaseIterable` (test support needs it; no behaviour change). Run → fails to compile.

### D10.2 Implement

A `ButtonStyle` with the circle fills of 19b §3.3–§3.4, `.help(title)`, `.accessibilityLabel(title)`, symbol from the
table in 19b §3.3, hover via `onHover` (no global monitor), keyboard focus ring kept.

Commit: `feat(ui): icon buttons for the island with today's titles as labels`

---

## Task D11 — Tab: family symbol, tokens (D-NL10, F5)

Files: `NotchHUDItem.swift` (`TabContent.Icon`: `.family(FormatFamily)`, `.action`), `NotchHUDBoard+Derived.swift`
(`icon(_:)` from the target's family via `FormatRegistry.standard`), `NotchGlyphs.swift` (remove `NotchIcon`'s Finder
icon and cache; symbol per family; ring 16 pt), `NotchTab.swift` (tokens), tests `NotchHUDBoardTests.swift`,
`NotchIconTests.swift` (rewritten), `NotchHUDBoardListTests.swift`.

### D11.1 Failing tests first

```swift
@Test func aWorkingJobShowsItsTargetsFamily() throws {
    let board = NotchHUDBoard().updating(try HUDFx.running(JobProgress(fraction: 0.4)), display: 1, now: t0)  // clip.mov → mp4
    #expect(board.tab(on: 1)?.icon == .family(.video))
}
@Test(arguments: FormatFamily.allCases) func everyFamilyHasASymbol(family: FormatFamily) {
    #expect(NotchSymbol.name(for: family) != nil)
}
@Test func aDoneActionShowsTheCheckMark() { #expect(NotchSymbol.name(for: ToastGlyph.action) == "checkmark.circle.fill") }
```

Update the existing tab expectations (`.file("clip.mov")` → `.family(.video)`). Run → fail.

### D11.2 Implement

As listed. The tab's count text uses `type.count`; glyph box 16; side inset `s`. No other behaviour change.

Commit: `feat(ui): the tab shows what kind of file is being made, in white symbols`

---

## Task D12 — Toast: two styles on one line (D-NL7, D-NL8)

Files: `NotchHUDCopy.swift` (`savedLine`, `failureLine` → `(primary: [LinePart], secondary: String?)`),
`NotchHUDBoard+Derived.swift` (`toastLine(on:)` keeps returning the joined M5a form for accessibility),
`NotchToast.swift`, `PartedLine.swift` if it needs a secondary style, tests `NotchLineTests.swift`,
`NotchHUDBoardTests.swift`.

### D12.1 Failing tests first

```swift
@Test func theSavedToastSplitsTheNameFromTheSizes() throws {
    let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
    let line = NotchHUDCopy.savedLine(done)
    #expect(LinePart.joined(line.primary) == "Saved photo.jpg" && line.secondary == "2.1 MB → 640 KB")
    #expect(NotchHUDBoard().updating(done, display: 1, now: t0).toastAccessibilityLabel(on: 1)
            == "Saved photo.jpg, 2.1 MB to 640 KB")                         // unchanged spoken form
}
@Test func theFailureToastKeepsTheWholeReason() { /* primary = reason without its full stop; secondary = name */ }
@Test func aLongNameGivesWayAndTheSizesStay() { /* 80-character name: primary gives way (Q25 unchanged) */ }
```

Run → fails to compile.

### D12.2 Implement

`NotchToast`: glyph (`symbol.toast`), primary in `type.primary`, secondary in `type.secondary` after `s` spacing, Undo
as `NotchIconButton` when offered; row height 36, side inset `m`.

Commit: `feat(ui): toasts say the result in one line without separators`

---

## Task D13 — Working card (F2, 19b §5)

Files: new `ZivletUI/Notch/NotchWorkingCard.swift`, `HUDCopy.swift` (`shortTimeLeft` *new*), `NotchCard.swift`
(route working items to the new view), tests `HUDCopyTests.swift` (or the existing copy test file),
new `NotchCardLayoutTests.swift`.

### D13.1 Failing tests first

```swift
@Test(arguments: [(5, "almost done"), (40, "< 1 min"), (190, "3 min"), (7_400, "2 hr")])
func theShortTimeLeftUsesTheSameThresholds(seconds: Int64, expected: String) {
    #expect(HUDCopy.shortTimeLeft(.seconds(seconds)) == expected)
}
@Test func theWorkingCardIsTwoRows() throws {
    let card = NotchWorkingCard(snapshot: try HUDFx.running(JobProgress(fraction: 0.4, eta: .seconds(40))), cancel: {})
    let size = try #require(ImageRenderer(content: card.frame(width: NotchCard.contentWidth)).nsImage).size
    #expect(size.height <= NotchLook.Card.workingHeight)    // two rows + insets; about 52 pt below the housing
}
@Test func theFirstRowSaysNameAndTarget() throws {
    #expect(NotchWorkingCard.title(for: try HUDFx.running(JobProgress(fraction: 0.4))) == "clip.mov → MP4")
}
@Test func cancelIsAnIconButtonWithItsTitle() { /* the card's presses == [.cancel] */ }
```

Run → fails to compile.

### D13.2 Implement

Row 1: family symbol, title (gives way), percent (`type.secondary`, monospaced digits). Row 2: a capsule bar 3 pt
(white on white 0.3, `VisibleProgress` with the bar's steps), short time left, Cancel icon button. No accent colour.
Spoken value unchanged (board's `accessibilityValue`). Update D2's key to include the short time left.

Commit: `feat(ui): the working card is two rows: name and target, bar and time`

---

## Task D14 — Result card (F1, F3)

Files: new `ZivletUI/Notch/NotchResultCard.swift`, `NotchCard.swift`, `NotchCardLayoutTests.swift`.

### D14.1 Failing tests first

```swift
@Test func theResultCardNamesTheFileOnce() throws {
    let model = ResultCardModel(try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg))
    let lines = NotchResultCard.lines(model)
    #expect(lines.primary == "Saved photo.jpg" && lines.secondary == "2.1 MB → 640 KB")
}
@Test func theButtonsAreTheModelsInItsOrder() { /* presses == state.visible(model) mapped: undo, reveal, open, copy */ }
@Test func theThumbnailIs40PointsWithTheInnerRadius() { /* NotchResultCard.thumbnailSide == 40, radius 8 */ }
@Test func theUndoReplyAndNotesAreCaptions() { /* undoMessage shown; height grows; host re-measures (existing test) */ }
```

Run → fails to compile.

### D14.2 Implement

Thumbnail (`FileDragSource`, drag callbacks unchanged) 40 pt, radius `inner`; primary and secondary lines; icon buttons
right-aligned on the second line when the line and buttons fit in the content width, else on a row below; notes and
undo reply as captions; details box radius `inner` with the M5a selectable text.

Commit: `feat(ui): the result card names the file once and its actions are symbols`

---

## Task D15 — Failure and action cards

Files: new `ZivletUI/Notch/NotchFailureCard.swift`, new `NotchActionCard.swift`, `NotchCard.swift`,
`NotchCardLayoutTests.swift`.

### D15.1 Failing tests first

```swift
@Test func theFailureCardLeadsWithTheReason() { /* primary = BatchPresentation title, up to 2 lines; secondary = name */ }
@Test func detailsToggleWithAChevronAndKeepTheirTitle() { /* press .showDetails; label "Show Details"; chevron.down→up */ }
@Test func retryAndCloseKeepTheirPressesAndCloseIsTheCancelAction() { /* keyboardShortcut(.cancelAction) on Close */ }
@Test func theActionCardShowsFiveLinesThenACount() { /* 7 lines → 5 + "and 2 more" (M5a string) */ }
```

Run → fails to compile.

### D15.2 Implement

As 19b §5; buttons through `NotchIconButton`; Escape behaviour unchanged (Close keeps `.cancelAction`).

Commit: `feat(ui): failure and action cards on the island in the same two styles`

---

## Task D16 — List rows

Files: `NotchList.swift`, `NotchHUDBoard+Derived.swift` (`row(_:)` gains a short status; "Failed" *new*),
`NotchHUDCopy.swift`, tests `NotchHUDBoardListTests.swift`.

### D16.1 Failing tests first

```swift
@Test func eachRowIsOneLine() { /* NotchHUDRow has title and status; status "40%", "2.1 MB → 640 KB", "Failed" */ }
@Test func rowPressesAreUnchanged() { /* working [.cancel]; saved [.reveal, .open]; failed batch [.retry, .close] … */ }
@Test func theSpokenListIsUnchanged() { /* accessibilityValue(on:) equals the M5a string for the same items */ }
```

Run → fails (no short status).

### D16.2 Implement

Row: ring or glyph (16), title (gives way), status right (`type.secondary`), icon buttons; row gap `s`; "+2 more" as
a caption.

Commit: `feat(ui): one line per job in the island's list`

---

## Task D17 — Content motion (D-NL13, 19b §3.4)

Files: `ZivletNotch/IslandAnimation.swift` (content transition per motion), `IslandChrome.swift`
(`.transition(…)` from the host), `NotchIconButton.swift` (hover animation off under Reduce Motion), tests
`IslandHostTests.swift`, `NotchIconButtonTests.swift`.

### D17.1 Failing tests first

```swift
@Test func contentEntersWithScaleAndFadeAndLeavesWithFade() {
    #expect(IslandAnimation.motion.contentTransition(reduceMotion: false) == .scaleAndFade(from: 0.96))
    #expect(IslandAnimation.motion.contentTransition(reduceMotion: true) == .fade)
}
@Test func reduceMotionNeverScalesContent() { /* host with curves(reduceMotion: true) → chrome.contentTransition == .fade */ }
@Test func buttonHoverIsInstantUnderReduceMotion() { /* NotchIconButton.hoverAnimation(reduceMotion: true) == nil */ }
```

Run → fails to compile.

### D17.2 Implement

A small equatable `IslandContentTransition` mapped to SwiftUI transitions in the chrome; the existing springs unchanged.

Commit: `feat(notch): content grows in with the island and only fades under Reduce Motion`

---

## Task D18 — Every state on screen: demo, screenshots, contrast check (D-ND4)

Files: `ZivletUI/Notch/IslandPreview.swift` (new states `list`, `actionToast`, `failureToast`), `App/AppDelegate+Demo.swift`
(the three flags of D-ND4), `ZivletNotch/ScreenGeometryReader.swift` (DEBUG pill override), new
`Scripts/demo-notch-states.sh`, new `Scripts/png-luminance.swift` (CoreGraphics; linear luminance of a box),
`Makefile` (`notch-states`), `Scripts/tests/test-notch-states.sh`, tests `IslandPreviewTests.swift`.

### D18.1 Failing tests first

```swift
@Test(arguments: ["list", "actionToast", "failureToast"]) func theNewPreviewStatesParse(value: String) throws {
    #expect(try IslandPreview.parse(arguments: ["-ZivletIslandPreview", value]) != nil)
}
@Test func theListPreviewHasSevenItemsOneFailed() { /* first() items → board rows 5, "+2 more", failed first */ }
```

```bash
test_states_script_lists_every_state() {      # dry run prints one capture per state × finish × display kind
  out=$(ZIVLET_STATES_DRY_RUN=1 Scripts/demo-notch-states.sh)
  for s in collapsed progress indeterminate expanded result failure failureToast actionToast list; do
    assert_contains "$out" "notch-$s-glass.png"; done
  assert_contains "$out" "pill-collapsed-glass.png"; assert_contains "$out" "notch-result-solid.png"
  assert_contains "$out" "notch-result-contrast.png"; assert_contains "$out" "notch-result-reduce-motion.png"
}
test_luminance_tool_reads_a_known_png() { assert_eq "$(xcrun swift Scripts/png-luminance.swift "$FIXTURE_GREY50" 0 0 4 4)" "0.214" }
```

Run → fail.

### D18.2 Implement

`demo-notch-states.sh` launches the Debug app once per state (×glass, solid, contrast for the result, toast and
card; pill for collapsed, toast and card; Reduce Motion mid-transition for the result), waits, captures the island's
frame from the app's `Island: frame` log line (D-M5a-14) into `build/notch-states/`, quits the app. With
`-ZivletIslandBackdrop white` it also captures the saved toast, the pill and the result card over a white panel and
runs `png-luminance.swift` on a text-free box; it fails when white 0.8 text would fall under 4.5:1 on any of them.
Nothing is written outside `build/`.

Verify: `make notch-states` → every file present, contrast lines printed; view each image.
Commit: `chore(scripts): capture every island state and check its contrast over white`

---

## Task D19 — QA list and cross-references

Files: `docs/plan/qa/notch.md`, `docs/design/19-notch.md` (one line under D-N10 and in §5.5 pointing to 19b),
`docs/design/19b-notch-look.md` (status line).

Changes to `qa/notch.md`:

- Q12 expected results: Reduce Motion fades only; Increase Contrast → solid with the outline and visible button
  backgrounds; Reduce Transparency → solid grey below the black band.
- New section F, "After the design pass (plan 14)":

| # | Check | Steps | Expected |
|---|---|---|---|
| Q27 | Glass legibility | Light wallpaper, then dark, then a busy photo; show a saved toast, a working card and the pill (`-ZivletIslandPill YES`) | All text readable; no part of a line looks washed out |
| Q28 | The band meets the menu bar | Light wallpaper with a translucent menu bar; open a card; screenshot | No seam between the housing and the band; the black beside the housing is acceptable (owner's call) |
| Q29 | The flare | Collapsed and expanded on the notch; look closely at the top corners; a crowded menu bar | The island grows out of the screen edge; it covers no menu title or status item while collapsed (Q13 still holds) |
| Q30 | Icon buttons | Hover each button; Voice Control "click Undo", "click Reveal", "click Retry"; Tab through them | Tooltips show today's words; Voice Control finds every button; the focus ring is visible |
| Q31 | Light appearance | Switch macOS to Light, show a toast and a card | The island stays dark with white text |
| Q32 | Motion | Hover the tab and the toast; with Reduce Motion on, again | Content grows in with the shape; under Reduce Motion only fades |

Commit (with D18's screenshots not tracked): `docs: QA rows for the island's design pass`

---

## Task D20 — Exit run and record

1. Gates (§3, "Full gates"), each under `nice -n 10`; `Scripts/m5a-exit.sh` rows X1–X7.
2. `make notch-idle` and `make notch-idle CONFIG=release`, with the new rows of 19b §6.3 (toast still, card still,
   pill with progress) added to `notch-idle.sh`'s states in this task (script test first: the dry run lists them).
3. `make notch-states`; send the owner the list of images (they stay in `build/`, not tracked).
4. Write `docs/plan/15-notch-design-record.md`: what was built (per task, with commits), gate numbers, X6 on Debug
   and Release with load averages, contrast readings from D18, decisions and deviations, known gaps (each 19b §4
   "not settled" item that is still open), owner steps (review screenshots of every state before merge, Q27–Q32,
   the M5a rows Q1–Q26 that are still open). G-M5a-1: closed only if progress passes on both builds; otherwise say
   which build and by how much.
5. Commit: `docs: record of the island's design pass`

---

## 5. Exit criteria

- Every task committed on `notch-design`, signed off, no `Co-Authored-By`, no file ≥ 800 lines, no function ≥ 50.
- All gates green; coverage ≥ 80 % in every gated module.
- X6 on Debug **and** Release: hidden and still states (tab, toast, card) ≤ 0.1 % over the baseline; progress, stepped
  glyph and pill with progress ≤ 1 %.
- D18's contrast check passes over white for the toast, the pill and the card.
- Screenshots of every state exist for the owner; the owner reviews them before merge (OWN-UI-1).
- The record says what was not measured: glass on macOS 26.x, WindowServer's share, the real Reduce Transparency and
  Increase Contrast settings (owner rows), 120 Hz.

## 6. Owner steps

| # | Step |
|---|---|
| OS-1 | Read 19b and this plan; answer the open points below |
| OS-2 | Review the screenshots from D18 (every state, three finishes, pill) before the branch is merged |
| OS-3 | Run Q27–Q32 and the open M5a rows on real hardware |
| OS-4 | Merge `notch-design` into `main` and push when satisfied (the assistant never pushes) |

Open points: (a) icon-only buttons versus words for Undo and Retry (19b D-NL9 picks symbols with tooltips);
(b) the tab's family symbol instead of the Finder icon (D-NL10); (c) whether "Saved" stays as the toast's first word
(kept, as the owner's own example in design/19 §4.3).

## 7. Risks

| Risk | Mitigation |
|---|---|
| The CPU change hides a real update (a dropped finished snapshot, a stale percent) | D3 tests: a finished snapshot always passes; the next visible step redraws within 250 ms |
| Glass contrast lower on the built island than in the probe | D18 measures the built surfaces over white and fails under 4.5:1; scrim is one token |
| Release measurement build drifts from the shipped build | It differs only by one compile condition; `release-check` scans the shipped binary for the preview flag |
| Screen-capture permission or a busy Mac stalls D18 or D20 | Run in the background with long timeouts; the record notes load averages and anything not captured |
| The look needs a rule change (frame sizes, timings) | Stop and ask; this plan changes no island rule |

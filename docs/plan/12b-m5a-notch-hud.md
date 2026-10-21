# 12b — M5a part 2: Notch HUD content, board, presenter, Settings, wiring, diagnostics, exit

Part of [12-implementation-plan-m5a-notch](12-implementation-plan-m5a-notch.md). Conventions: index §5. Design:
[design/19-notch](../design/19-notch.md) §4.3, §5–§7. Swift below is specification-grade and was not compiled for
this plan. Test fixtures reuse `HUDFx` (`Tests/ZivletUITests/HUDFixtures.swift`).

---

## Task N8 — Surface-free HUD content (refactor; design/19 §7)

| Field | Value |
|---|---|
| Goal | Split each HUD view into content and surface, with no change on screen: `ResultCardContent` (today's `ResultCard` body without `.padding`, the 360 pt frame and `.hudGlass()`), `WorkingContent` (today's `ResultHUDView.working` body), `ActionContent` (today's `ActionHUDView` body). `ResultCard`, `ResultHUDView` and `ActionHUDView` become thin wrappers that add today's padding, frame and glass. The content views take a `width` so the island can lay them out at 360 pt inside its 380 pt card |
| Acceptance | `ResultCardTests`, `HUDTests`, `ActionHUDTests`, `SettingsPaneSnapshotTests` pass unchanged; `make convert-demo FILE=… TO=png` prints the same `Result card: …` line before and after; no file in `ZivletUI/HUD` grows past 250 lines |
| Effort | S |

**Files:** create `Sources/ZivletUI/HUD/ResultCardContent.swift`, `Sources/ZivletUI/HUD/WorkingContent.swift`,
`Sources/ZivletUI/HUD/ActionContent.swift`; modify `ResultCard.swift`, `ResultHUDView.swift`, `ActionHUDView.swift`.

TDD for a refactor: run `swift test --filter "ResultCard|HUD|ActionHUD"` first (green), move code, run again
(green). No new behaviour, so no new failing test; N10 adds the island's own view tests.

Commit `refactor(ui): split the HUD views into content and surface so the island can reuse them`.

---

## Task N9 — `NotchHUDBoard` (pure; design/19 §4.3, §4.4, §5.5; D-N7, D-M5a-3)

| Field | Value |
|---|---|
| Goal | A value type in `ZivletUI` (no AppKit): items per display, each a conversion batch (`BatchSnapshot`) or an action result (`ActionResult` + optional undo `BatchID`); `updating(_ snapshot:, display:, now:)`, `updating(_ action:, display:, now:)`, `hovering(_:, display:, now:)`, `closing(_ id:, now:)`, `expiring(now:)`. Derived per display: `request: IslandRequest?` (resting surface, hover surface, sticky, content height), `ears: EarContent` (icon kind, ring fraction or spinner, count label), `toastLine: String?`, `rows: [Row]` for the list (at most 5 plus "+n more"), `nextDeadline: Duration?`, `announcements: [Announcement]` (emitted once per event), `redraw: Bool` for progress (only when the shown percent changes and ≥ 250 ms since the last redraw). Lingers reuse `LingerTimer` with `ResultCardModel.successLinger`, `ActionHUD.toastLinger`, `ActionHUD.undoLinger`. Copy reuses `HUDCopy`, `ResultCardModel`, `BatchPresentation`, `ActionResult.toast`; new strings: "Saved " prefix of the toast (owner's example), "\(n) jobs", "+\(n) more" (*new*) |
| Acceptance | tests below green; `ZivletUI` coverage stays ≥ 80 % |
| Effort | M |

**Files:** create `Sources/ZivletUI/Notch/NotchHUDBoard.swift`, `Sources/ZivletUI/Notch/NotchHUDItem.swift`,
`Sources/ZivletUI/Notch/NotchHUDCopy.swift`, `Tests/ZivletUITests/NotchHUDBoardTests.swift`,
`Tests/ZivletUITests/NotchHUDBoardListTests.swift`.

### N9.1 Failing tests first

```swift
@Suite("Notch HUD board: one item (P2-116, design/19 §4.3)")
struct NotchHUDBoardTests {
    let t0 = Duration.seconds(100)

    @Test func aWorkingJobRestsCollapsedWithItsIconAndRing() throws {
        let board = NotchHUDBoard().updating(try HUDFx.running(JobProgress(fraction: 0.4)), display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .collapsed)
        #expect(board.ears(on: 1) == EarContent(icon: .file("clip.mov"), ring: .fraction(0.4), count: nil))
    }

    @Test func aSavedJobShowsTheSavedToastForFourSeconds() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
        let board = NotchHUDBoard().updating(done, display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .toast)
        #expect(board.toastLine(on: 1) == "Saved photo.jpg · 2.1 MB → 640 KB")
        #expect(board.nextDeadline == t0 + .seconds(4))
        #expect(board.expiring(now: t0 + .seconds(4)).request(on: 1) == nil)
    }

    @Test func hoverHoldsTheToastAndLeavingRestartsTheFullLinger() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        var board = NotchHUDBoard().updating(done, display: 1, now: t0).hovering(true, display: 1, now: t0 + .seconds(3))
        #expect(board.expiring(now: t0 + .seconds(30)).request(on: 1) != nil)
        board = board.hovering(false, display: 1, now: t0 + .seconds(30))
        #expect(board.nextDeadline == t0 + .seconds(34))
    }

    @Test func aFailureIsAStickyExpandedCardWithNoLinger() throws {
        let board = NotchHUDBoard().updating(try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom")), display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .expanded && board.request(on: 1)?.sticky == true)
        #expect(board.nextDeadline == nil)
    }

    @Test func anActionToastLeavesAfter1500msOr4sWithUndo() {
        let plain = NotchHUDBoard().updating(.done(toast: "Copied 1 file", undo: nil), display: 1, now: t0)
        #expect(plain.nextDeadline == t0 + .milliseconds(1_500))
        let move = NotchHUDBoard().updating(.done(toast: "Moved 1 file", undo: BatchID()), display: 1, now: t0)
        #expect(move.nextDeadline == t0 + .seconds(4) && move.toastLine(on: 1) == "Moved 1 file")
    }

    @Test func aCancelledActionShowsNothing() {
        #expect(NotchHUDBoard().updating(ActionResult.cancelled, display: 1, now: t0).request(on: 1) == nil)
    }

    @Test func closingTheLastItemWithdrawsTheRequest() { /* failure, closing(id) → request nil */ }
    @Test func aResultWhileHoveredDoesNotCollapse() { /* hovering(true), job finishes → hover surface stays expanded */ }
}

@Suite("Notch HUD board: several items, displays, announcements, redraw")
struct NotchHUDBoardListTests {
    @Test func twoJobsShowTheCountAndACombinedRing() { /* ears.count == "2 jobs", ring = mean of working fractions */ }
    @Test func theListShowsFiveRowsThenMore() { /* 7 items → 5 rows + "+2 more" */ }
    @Test func eachRowLeavesByItsOwnRule() { /* saved row expires at 4 s, working row stays */ }
    @Test func itemsAreKeptPerDisplay() { /* job on 1, job on 2 → each request alone, no "2 jobs" */ }
    @Test func announcesStartSavedFailedAndToastOnceButNeverPercentages() {
        /* start → "Converting to PNG, file0.heic" (medium) once; progress updates → none;
           saved → "Saved photo.jpg" (medium); failed → the card title (high); toast → its text (medium) */
    }
    @Test func progressRedrawsOnlyWhenThePercentChangesAtMostFourTimesASecond() {
        /* 0.401, 0.402 at +100 ms → no redraw; 0.41 at +100 ms → no (< 250 ms); 0.41 at +260 ms → redraw */
    }
}
```

`EarContent`, `Row` and `Announcement` are plain `Equatable` values defined in `NotchHUDItem.swift`.

RED: `cannot find 'NotchHUDBoard'`. GREEN: `swift test --filter NotchHUDBoard`.

Commit `feat(ui): Notch HUD board with lingers, job count, list rows and announcements`.

---

## Task N10 — `NotchHUD` presenter, island views and presenter protocols (design/19 §4.3, §5.4–§5.5, §7; D-N10)

| Field | Value |
|---|---|
| Goal | **Protocols** `HUDPresenter` (`prepare(near:)`, `show(_ snapshot:)`, `close(_ batch:)`, the five callbacks) and `ActionPresenter` (`show(_ result:, near:)`, `onUndo`); `ResultHUD` and `ActionHUD` conform with no behaviour change. **`NotchHUD`** conforms to both: keeps the drop point of the next batch or action (as `ResultHUD.prepare(near:)` does), finds its display through `IslandLayout.display(for:in:)` on the provider's displays, updates the board, sends the board's request to `IslandHosts` as the `.hud` client, schedules the board's next deadline, posts the board's announcements, and routes presses to the same callbacks `ResultHUD` uses (Undo asked once while pending, as `CardState`/`ActionHUDModel` do today). Signpost interval `drop→island` (category `hud`). **Views** (`Sources/ZivletUI/Notch/`): `NotchEars` (icon left, ring or count right; the ring is a `Circle().trim` redrawn only when the board says `redraw`), `NotchToast` (check mark or action icon + the toast line + Undo when offered), `NotchCard` (wraps `WorkingContent`, `ResultCardContent` or `ActionContent` at 360 pt, top padding = housing height on a notch display), `NotchList` (rows with their own ring or result and buttons). All on solid black with `.environment(\.colorScheme, .dark)`; Increase Contrast adds a 1 pt white outline at 0.5. Accessibility: the island group's label "Zivlet progress and results" (*new*) and its value = the expanded text (D-M5a-4) |
| Acceptance | tests below green; `make app` builds; `ResultHUD`/`ActionHUD` tests unchanged |
| Effort | M |

**Files:** create `Sources/ZivletUI/HUD/HUDPresenter.swift`, `Sources/ZivletUI/Notch/NotchHUD.swift`,
`Sources/ZivletUI/Notch/NotchHUD+Actions.swift`, `Sources/ZivletUI/Notch/NotchEars.swift`,
`Sources/ZivletUI/Notch/NotchToast.swift`, `Sources/ZivletUI/Notch/NotchCard.swift`, `Sources/ZivletUI/Notch/NotchList.swift`,
`Sources/ZivletUI/Notch/NotchInk.swift`; modify `ResultHUD.swift`, `ActionHUD.swift` (conformance only);
tests `Tests/ZivletUITests/NotchHUDTests.swift`, `Tests/ZivletUITests/NotchHUDTimingTests.swift`,
`Tests/ZivletUITests/NotchInkTests.swift`.

### N10.1 Failing tests first

```swift
@Suite("Notch HUD presenter (P2-116)")
@MainActor
struct NotchHUDTests {
    @Test func theIslandOpensOnTheDisplayOfTheDrop() throws {
        let displays = FakeDisplayProvider.notchAndExternal()          // ids 1 (notch) and 2 (plain, at x −7000)
        let hud = NotchHUD(provider: displays)
        hud.prepare(near: CGPoint(x: -6500, y: 400))
        hud.show(try HUDFx.snapshot(submitted: 1))
        #expect(hud.hosts.visibleDisplays == [2])
        #expect(hud.hosts.surface(on: 2) == .collapsed)
    }

    @Test func cancelInTheIslandCancelsItsOwnBatch() throws {
        let hud = NotchHUD(provider: FakeDisplayProvider.notchOnly())
        var cancelled: [BatchID] = []
        hud.onCancel = { cancelled.append($0) }
        let snapshot = try HUDFx.running(JobProgress(fraction: 0.2))
        hud.show(snapshot)
        hud.press(.cancel, on: snapshot.batch)   // NotchHUD.Press = the card buttons plus .cancel
        #expect(cancelled == [snapshot.batch])
    }

    @Test func undoIsAskedOnceWhileItsReplyIsPending() async throws { /* two presses → onUndo called once */ }
    @Test func revealOpenAndCopySkipOutputsAnUndoTrashed() async throws { /* as ResultHUD.press does */ }
    @Test func anActionToastUsesTheIslandAndLeaves() async { /* show(.done(toast:"Copied 1 file")) → toast, then hidden */ }
    @Test func resultHUDAndActionHUDStillWorkThroughTheProtocols() throws {
        let presenter: any HUDPresenter = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        presenter.prepare(near: nil)
        presenter.show(try HUDFx.snapshot(submitted: 1))
        #expect((presenter as? ResultHUD)?.isVisible == true)
    }
}

@Suite("Notch HUD appears quickly (P1-40 budget: ≤ 50 ms)")
@MainActor
struct NotchHUDTimingTests {
    @Test func aDropShowsTheIslandWithin50ms() throws {
        let hud = NotchHUD(provider: FakeDisplayProvider.notchOnly())   // host pre-warmed at init (D-N9)
        let start = ContinuousClock.now
        hud.prepare(near: CGPoint(x: -4500, y: -4500))
        hud.show(try HUDFx.snapshot(submitted: 1))
        #expect(hud.hosts.surface(on: 1) == .collapsed)
        #expect(ContinuousClock.now - start < .milliseconds(50))
    }
}

@Suite("Island ink (D-N10, NFR-14 ≥ 4.5:1)")
struct NotchInkTests {
    @Test func whiteAndSecondaryTextOnBlackPassWithMargin() {
        #expect(NotchInk.contrast(textOpacity: 1) > 20)
        #expect(NotchInk.contrast(textOpacity: NotchInk.secondaryOpacity) >= 4.5)
    }
}
```

`FakeDisplayProvider` lives in `Tests/ZivletUITests/` and places every display off screen. `NotchInk.contrast`
reuses `HUDInk.luminance`.

RED: `cannot find 'NotchHUD'`. GREEN: `swift test --filter "NotchHUD|NotchInk|ResultCard|ActionHUD"`, `make app`.

Commit `feat(ui): Notch HUD shows progress, results and action toasts on the island`.

---

## Task N11 — Settings › General row and app wiring (design/19 §5.1, §6; D-M5a-2, D-M5a-6)

| Field | Value |
|---|---|
| Goal | **Settings:** a "Progress and results" (*new*) section in `GeneralPane` with the picker "Show progress and results:" (*new*) offering "At the notch" (*new*; "At the top of the screen" (*new*) on a Mac without a built-in notch) and "Near the drop" (*new*, OP-2); the selection shows `placement.resolved(hasBuiltInNotch:)`; choosing stores the explicit value. The label strings are constants in `PlacementCopy`. `SettingsModel` gets `hasBuiltInNotch` from the app (via `ScreenGeometryReader`: a built-in display, `CGDisplayIsBuiltin`, with a housing). **Router:** pure `PresenterRouter.route(placement:hasBuiltInNotch:) -> Route` (`.notch` or `.nearDrop`), called per drop by `ConversionWiring` and `ActionWiring`, which now hold both presenters (`ResultHUD` + `NotchHUD`, `ActionHUD` + `NotchHUD`) and pass the drop to the routed one. **Wheel:** the app's wheel wiring sends `wheelShown` / `wheelHidden` to `IslandHosts`. **Reduce Motion:** observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and forward `reduceMotionChanged`. **Logging:** `Island: <surface>` notice lines (surface names only, public) for the demo; file names stay private as today |
| Acceptance | tests below green; `make app`; manual: `make convert-demo FILE=… TO=jpeg PLACEMENT=notch` shows the island, `PLACEMENT=nearDrop` today's card |
| Effort | S |

**Files:** create `Sources/ZivletUI/Notch/PresenterRouter.swift`, `Sources/ZivletUI/Settings/PlacementCopy.swift`,
`Tests/ZivletUITests/PresenterRouterTests.swift`, `Tests/ZivletUITests/PlacementSettingsTests.swift`; modify
`Sources/ZivletUI/Settings/GeneralPane.swift`, `Sources/ZivletUI/Settings/SettingsModel.swift`,
`App/ConversionWiring.swift`, `App/ActionWiring.swift`, `App/AppDelegate.swift` (create `IslandHosts`,
`ScreenGeometryReader`), the wheel wiring file that shows and hides the wheel, `App/SettingsWiring.swift`,
`Scripts/demo-convert.sh` (optional 4th argument → `-ZivletHUDPlacement`), `Makefile` (`PLACEMENT` passed through).

### N11.1 Failing tests first

```swift
@Suite("Presenter router (D-M5a-2)")
struct PresenterRouterTests {
    @Test func automaticFollowsTheMac() {
        #expect(PresenterRouter.route(placement: .automatic, hasBuiltInNotch: true) == .notch)
        #expect(PresenterRouter.route(placement: .automatic, hasBuiltInNotch: false) == .nearDrop)
    }

    @Test func anExplicitChoiceWinsOnEveryMac() {
        #expect(PresenterRouter.route(placement: .nearDrop, hasBuiltInNotch: true) == .nearDrop)
        #expect(PresenterRouter.route(placement: .notch, hasBuiltInNotch: false) == .notch)
    }
}

@Suite("Placement in Settings › General (design/19 §6)")
@MainActor
struct PlacementSettingsTests {
    @Test func theNotchChoiceIsNamedForTheMac() {
        #expect(PlacementCopy.notchLabel(hasBuiltInNotch: true) == "At the notch")
        #expect(PlacementCopy.notchLabel(hasBuiltInNotch: false) == "At the top of the screen")
        #expect(PlacementCopy.nearDropLabel == "Near the drop")
    }

    @Test func theSelectionShowsTheResolvedValueAndAChoiceIsStored() {
        let model = SettingsModel.testModel(hasBuiltInNotch: true)        // existing test helper pattern
        #expect(model.shownPlacement == .notch)
        model.choosePlacement(.nearDrop)
        #expect(model.settings.hud.placement == .nearDrop)
    }
}
```

Plus the existing `SettingsPaneSnapshotTests` gains one snapshot of the General pane with the new section.

RED: `cannot find 'PresenterRouter'`. GREEN: `swift test --filter "PresenterRouter|PlacementSettings|SettingsPane"`,
`make app`, then the two manual demos (quit the app afterwards with `osascript -e 'quit app "Zivlet"'`).

Commits `feat(ui): Settings choice for where progress and results show` and
`feat(app): route each drop to the notch island or the card near the drop`.

---

## Task N12 — Display geometry in Copy Diagnostics (design/19 §3.3; OP-5)

| Field | Value |
|---|---|
| Goal | `DisplayGeometry.diagnosticsLine` (pure, `ZivletNotchCore`): "display 1: frame 0 0 1800 1169 · visible 0 94 1800 1036 · safe top 38 · aux left 0 1131 790 38 · aux right 1010 1131 790 38 · housing 790 1131 220 38" (*new* format, no names). `DiagnosticsSources` gains `displays: [String]` and `Diagnostics.build` prints a "Displays" section; the app fills it from `ScreenGeometryReader` |
| Acceptance | tests below green; the redaction tests still pass (no home path can appear in these lines) |
| Effort | S |

**Files:** modify `Sources/ZivletNotchCore/DisplayGeometry.swift`, `Sources/ZivletRuntime/Diagnostics.swift`,
`App/SettingsWindowWiring.swift`; tests `Tests/ZivletNotchCoreTests/DisplayDiagnosticsTests.swift`,
`Tests/ZivletRuntimeTests/DiagnosticsTests.swift` (one new case).

```swift
@Suite("Display geometry in diagnostics (Q15)")
struct DisplayDiagnosticsTests {
    @Test func oneLinePerDisplayWithEveryValueAndTheHousing() throws {
        #expect(try DisplayFixtures.mbp14MoreSpace().diagnosticsLine ==
            "display 1: frame 0 0 1800 1169 · visible 0 94 1800 1036 · safe top 38 · aux left 0 1131 790 38 · aux right 1010 1131 790 38 · housing 790 1131 220 38")
    }

    @Test func aDisplayWithoutANotchSaysSo() throws {
        #expect(try DisplayFixtures.noNotch1080().diagnosticsLine.hasSuffix("· housing none"))
    }
}
```

RED: `value of type 'DisplayGeometry' has no member 'diagnosticsLine'`. GREEN: both suites.

Commit `feat(ui): display geometry in Copy Diagnostics so notch sizes can be recorded`.

---

## Task N13 — QA list, exit runner, idle-CPU sampler, exit run and record

| Field | Value |
|---|---|
| Goal | `docs/plan/qa/notch.md`: owner rows Q1–Q17 from design/19 §10, each with steps, expected result and a result column. `Scripts/idle-cpu.sh PID SECONDS` (samples `ps -o time=` at start and end, prints CPU % with two decimals; exits 2 on a missing process). `Scripts/m5a-exit.sh` with rows X1–X7 of the index §6, logs in `build/m5a-exit/`, the same structure as `Scripts/m4-exit.sh` (row list, `--row Xn`, summary table); the TCC row counts tccd requests with `preflight=no` attributed to Zivlet and lists the preflight checks separately (D-M5a-5). `make notch-demo` runs the conversion demo with the notch placement and captures the island region with `screencapture -x -R` from the `Island: frame …` notice line. `make m5a-exit`. Then run it and write `docs/plan/13-m5a-record.md` (contents, commits, gates, decisions, gaps, owner steps), honest about every row that did not pass or was not run |
| Acceptance | `Scripts/tests/test-m5a-exit.sh` and `Scripts/tests/test-idle-cpu.sh` pass under `make script-test` (rows stubbed, as `test-m4-exit.sh` does); `make m5a-exit` run once with its results in the record |
| Effort | S |

**Files:** create `docs/plan/qa/notch.md`, `Scripts/idle-cpu.sh`, `Scripts/m5a-exit.sh`, `Scripts/demo-notch.sh`,
`Scripts/tests/test-m5a-exit.sh`, `Scripts/tests/test-idle-cpu.sh`, `docs/plan/13-m5a-record.md`; modify `Makefile`.

### N13.1 Failing tests first

`Scripts/tests/test-idle-cpu.sh`: a stub `ps` on `PATH` that prints `0:01.00` then `0:01.10` → the script prints
`0.50` for 20 s; a missing PID → exit 2 with "no process". `Scripts/tests/test-m5a-exit.sh`: with every row command
stubbed to succeed, the summary lists X1–X7 as pass; with the TCC stub returning one `preflight=no` line for Zivlet,
X5 fails; with only `preflight=yes` lines, X5 passes and lists them.

RED: `Scripts/idle-cpu.sh: No such file or directory`. GREEN: `make script-test`.

Commits `test(scripts): M5a exit runner, idle-CPU sampler and the notch demo`,
`docs: owner QA list for the notch island and the Notch HUD`, and after the run
`docs: M5a record: notch island core and Notch HUD`.

---

## After N13

The owner reviews the commits and the record, runs `docs/plan/qa/notch.md` on real hardware (an external display,
full screen, Stage Manager, VoiceOver, a crowded menu bar), and answers OP-1 … OP-5 (index §7). M5b starts with NB1
(index §9).

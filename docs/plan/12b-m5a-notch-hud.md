# 12b — M5a part 2: Notch HUD content, board, presenter, Settings, wiring, diagnostics, exit

Part of [12-implementation-plan-m5a-notch](12-implementation-plan-m5a-notch.md). Conventions: index §5. Design:
[design/19-notch](../design/19-notch.md) §4.3, §5–§7. Swift below is specification-grade and was not compiled for
this plan. Test fixtures reuse `HUDFx` (`Tests/ZivletUITests/HUDFixtures.swift`).

---

## Task N8 — Surface-free HUD content (refactor) and one clock for `ResultHUD`'s lingers (design/19 §7, D-N11)

| Field | Value |
|---|---|
| Goal | Split each HUD view into content and surface, with no change on screen: `ResultCardContent` (today's `ResultCard` body without `.padding`, the 360 pt frame and `.hudGlass()`), `WorkingContent` (today's `ResultHUDView.working` body), `ActionContent` (today's `ActionHUDView` body). `ResultCard`, `ResultHUDView` and `ActionHUDView` become thin wrappers that add today's padding, frame and glass. The content views take a `width` so the island can lay them out at 360 pt inside its 380 pt card. **Fix (TDD):** `ResultHUD` reads `now` from `systemUptime` but sleeps with `Task.sleep(for:)`, so a linger that spans system sleep never ends (D-N11). It gets an injected clock (default `ContinuousClock`), sleeps until the deadline on that clock, and reschedules when a wake finds the deadline not yet reached |
| Acceptance | `ResultCardTests`, `HUDTests`, `ActionHUDTests`, `SettingsPaneSnapshotTests` pass unchanged; the new `ResultHUDClockTests` pass; `make convert-demo FILE=… TO=png` prints the same `Result card: …` line before and after; no file in `ZivletUI/HUD` grows past 250 lines |
| Effort | S |

**Files:** create `Sources/ZivletUI/HUD/ResultCardContent.swift`, `Sources/ZivletUI/HUD/WorkingContent.swift`,
`Sources/ZivletUI/HUD/ActionContent.swift`; modify `ResultCard.swift`, `ResultHUDView.swift`, `ActionHUDView.swift`.

TDD for a refactor: run `swift test --filter "ResultCard|HUD|ActionHUD"` first (green), move code, run again
(green). No new behaviour, so no new failing test; N10 adds the island's own view tests.

The clock fix is behaviour, so it starts with a failing test in `Tests/ZivletUITests/ResultHUDClockTests.swift`:

```swift
@Suite("ResultHUD lingers survive system sleep (D-N11)")
@MainActor
struct ResultHUDClockTests {
    @Test func aWakeBeforeTheDeadlineReschedulesAndTheCardStillLeaves() async throws {
        let clock = SteppedClock()                      // test clock: sleeps return early once, then on time
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] }, clock: clock)
        hud.show(try HUDFx.finished(outputs: [("a.png", before: 1, after: 1)], target: .png))
        await clock.wakeEarly(by: .seconds(1))          // the first sleep ends 1 s before the deadline
        #expect(hud.isVisible)                          // not yet expired: rescheduled, not dropped
        await clock.advance(by: .seconds(1))
        #expect(!hud.isVisible)
    }
}
```

RED today: the second expectation fails (the card never leaves). Modify `ResultHUD.swift` (clock parameter, sleep
until the deadline, reschedule) and create the test file and `Tests/ZivletUITests/SteppedClock.swift`.

Commits `refactor(ui): split the HUD views into content and surface so the island can reuse them` and
`fix(ui): HUD card lingers use one clock and end after the Mac wakes`.

---

## Task N9 — `NotchHUDBoard` (pure; design/19 §4.3, §4.4, §5.5; D-N7, D-M5a-3)

| Field | Value |
|---|---|
| Goal | A value type in `ZivletUI` (no AppKit): items per display, each a conversion batch (`BatchSnapshot`) or an action result (`ActionResult` + optional undo `BatchID`); `updating(_ snapshot:, display:, now:)`, `updating(_ action:, display:, now:)`, `holding(_:, display:, now:)` (the host's `held` effect: hover, accessibility focus or a drag from the island, D-N13), `closing(_ id:, now:)`, `expiring(now:)`, `movingItems(from:to:)` (a removed display's items go to its replacement, design/19 §5.2), and an `assistiveTech: Bool` input (VoiceOver or Switch Control running) that triples toast lingers. Derived per display: `request: IslandRequest?` (resting and hover surface only; the host measures the height, so the board never guesses it), `tab: TabContent` (icon kind, ring fraction or stepped glyph, count label, error marker), `toastLine: String?` and `toastAccessibilityLabel: String?` (separators as words), `rows: [Row]` for the list (failed rows first, at most 5 plus "+n more"), `nextDeadline: Duration?`, `announcements: [Announcement]` (emitted once per event), `redraw: Bool` for progress and the stepped glyph (only when the shown percent or step changes and ≥ 250 ms since the last redraw). A failure rests as a toast for 4 s, then collapsed with the error marker, and stays until closed, retried or undone (design/19 §4.3). Lingers reuse `LingerTimer` with `ResultCardModel.successLinger`, `ActionHUD.toastLinger`, `ActionHUD.undoLinger`. Copy reuses `HUDCopy`, `ResultCardModel`, `BatchPresentation`, `ActionResult.toast`; new strings: "Saved " prefix of the toast (owner's example), "\(n) jobs", "+\(n) more", the toast's spoken form (*new*) |
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
        #expect(board.tab(on: 1) == TabContent(icon: .file("clip.mov"), ring: .fraction(0.4), count: nil, failed: false))
    }

    @Test func aJobOfUnknownLengthShowsTheSteppedGlyph() { /* fraction nil → ring == .step(0); +250 ms → .step(1), redraw */ }

    @Test func aSavedJobShowsTheSavedToastForFourSeconds() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 2_100_000, after: 640_000)], target: .jpg)
        let board = NotchHUDBoard().updating(done, display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .toast)
        #expect(board.toastLine(on: 1) == "Saved photo.jpg · 2.1 MB → 640 KB")
        #expect(board.toastAccessibilityLabel(on: 1) == "Saved photo.jpg, 2.1 MB to 640 KB")
        #expect(board.nextDeadline == t0 + .seconds(4))
        #expect(board.expiring(now: t0 + .seconds(4)).request(on: 1) == nil)
    }

    @Test func hoverHoldsTheToastAndLeavingRestartsTheFullLinger() throws {
        let done = try HUDFx.finished(outputs: [("photo.jpg", before: 1, after: 1)], target: .jpg)
        var board = NotchHUDBoard().updating(done, display: 1, now: t0).holding(true, display: 1, now: t0 + .seconds(3))
        #expect(board.expiring(now: t0 + .seconds(30)).request(on: 1) != nil)
        board = board.holding(false, display: 1, now: t0 + .seconds(30))
        #expect(board.nextDeadline == t0 + .seconds(34))
    }

    @Test func aFailureShowsAToastThenWaitsInTheTabUntilClosed() throws {
        let board = NotchHUDBoard().updating(try HUDFx.failed(error: .processFailed(status: 1, stderrTail: "boom")), display: 1, now: t0)
        #expect(board.request(on: 1)?.resting == .toast)
        let later = board.expiring(now: t0 + .seconds(4))
        #expect(later.request(on: 1)?.resting == .collapsed && later.tab(on: 1)?.failed == true)
        #expect(later.nextDeadline == nil)
    }

    @Test func lingersAreThreeTimesAsLongWithAssistiveTech() { /* assistiveTech true: saved toast deadline t0 + 12 s */ }

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
    @Test func aResultWhileHeldDoesNotCollapse() { /* holding(true), job finishes → hover surface stays expanded */ }
    @Test func theEndOfADragRestartsTheFullLinger() { /* holding(true) at +1 s (drag), holding(false) at +9 s → deadline +13 s */ }
}

@Suite("Notch HUD board: several items, displays, announcements, redraw")
struct NotchHUDBoardListTests {
    @Test func twoJobsShowTheCountAndACombinedRing() { /* tab.count == "2 jobs", ring = mean of working fractions */ }
    @Test func aFailureAmongSeveralMarksTheTabAndListsFirst() { /* 1 failed + 2 working → tab.failed, rows[0] is the failure */ }
    @Test func severalFailuresAreRowsNotStackedCards() { /* 2 failures → one request, two failed rows */ }
    @Test func aRemovedDisplaysItemsMoveToItsReplacement() { /* items on 2, movingItems(from: 2, to: 1) → request on 1 counts them */ }
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

`TabContent`, `Row` and `Announcement` are plain `Equatable` values defined in `NotchHUDItem.swift`.

RED: `cannot find 'NotchHUDBoard'`. GREEN: `swift test --filter NotchHUDBoard`.

Commit `feat(ui): Notch HUD board with lingers, job count, list rows and announcements`.

---

## Task N10 — `NotchHUD` presenter, island views and presenter protocols (design/19 §4.3, §5.4–§5.5, §7; D-N10)

| Field | Value |
|---|---|
| Goal | **Protocols** `HUDPresenter` (`prepare(near:)`, `show(_ snapshot:)`, `close(_ batch:)`, the five callbacks, with `onRetry: (BatchID, CGPoint?) -> Void` carrying the source batch and the anchor for the new one) and `ActionPresenter` (`show(_ result:, near:)`, `onUndo`); `ResultHUD` and `ActionHUD` conform. The one behaviour change: `ResultHUD.retry` no longer calls its own `prepare(near:)`; it closes the card and reports `(batch, anchor)`, and the wiring routes the new batch (N11). **`NotchHUD(hosts:provider:)`** takes the one `IslandHosts` that `AppDelegate` builds (it never creates its own) and registers as the `.hud` client; it conforms to both protocols: keeps the drop point of the next batch or action (as `ResultHUD.prepare(near:)` does) and of each open batch (Retry reports it), finds its display through `IslandLayout.display(for:in:)` on the provider's displays, updates the board, sends the board's request to `IslandHosts` as the `.hud` client, schedules the board's next deadline, posts the board's announcements, and routes presses to the same callbacks `ResultHUD` uses (Undo asked once while pending, as `CardState`/`ActionHUDModel` do today). Signpost interval `drop→island` (category `hud`). **Views** (`Sources/ZivletUI/Notch/`): `NotchTab` (icon left, count text in the middle, ring, stepped glyph or error glyph right; the ring is a `Circle().trim` with fill white and track white at 0.4, redrawn only when the board says `redraw`), `NotchToast` (check mark, error glyph or action icon + the toast line + Undo when offered; its accessibility label is the board's spoken form), `NotchCard` (wraps `WorkingContent`, `ResultCardContent` or `ActionContent` at 360 pt, top padding = housing height on a notch display), `NotchList` (rows with their own ring or result and buttons). All on solid black with `.environment(\.colorScheme, .dark)`; Increase Contrast adds a 1 pt white outline at 0.5. Accessibility: the island group's label "Zivlet progress and results" (*new*), its value = the expanded text (D-M5a-4), and a custom action "Show Progress and Results" (D-N12) |
| Acceptance | tests below green; `make app` builds; `ResultHUD`/`ActionHUD` tests unchanged |
| Effort | M |

**Files:** create `Sources/ZivletUI/HUD/HUDPresenter.swift`, `Sources/ZivletUI/Notch/NotchHUD.swift`,
`Sources/ZivletUI/Notch/NotchHUD+Actions.swift`, `Sources/ZivletUI/Notch/NotchTab.swift`,
`Sources/ZivletUI/Notch/NotchToast.swift`, `Sources/ZivletUI/Notch/NotchCard.swift`, `Sources/ZivletUI/Notch/NotchList.swift`,
`Sources/ZivletUI/Notch/NotchInk.swift`; modify `ResultHUD.swift` (conformance; Retry reports its anchor instead of
queueing it), `ActionHUD.swift` (conformance only);
tests `Tests/ZivletUITests/NotchHUDTests.swift`, `Tests/ZivletUITests/NotchHUDTimingTests.swift`,
`Tests/ZivletUITests/NotchInkTests.swift`.

### N10.1 Failing tests first

```swift
@Suite("Notch HUD presenter (P2-116)")
@MainActor
struct NotchHUDTests {
    @Test func theIslandOpensOnTheDisplayOfTheDrop() throws {
        let displays = FakeDisplayProvider.notchAndExternal()          // ids 1 (notch) and 2 (plain, at x −7000)
        let hosts = IslandHosts(provider: displays)
        let hud = NotchHUD(hosts: hosts, provider: displays)
        hud.prepare(near: CGPoint(x: -6500, y: 400))
        hud.show(try HUDFx.snapshot(submitted: 1))
        #expect(hosts.visibleDisplays == [2])
        #expect(hosts.surface(on: 2) == .collapsed)
    }

    @Test func cancelInTheIslandCancelsItsOwnBatch() throws {
        let displays = FakeDisplayProvider.notchOnly()
        let hud = NotchHUD(hosts: IslandHosts(provider: displays), provider: displays)
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
    @Test func retryReportsTheSourceBatchAndItsDropPoint() throws { /* failed batch dropped at p, press .retry → onRetry(batch, p) */ }
    @Test func resultHUDRetryNoLongerQueuesItsOwnAnchor() throws { /* ResultHUD retry → onRetry(batch, anchor); next show uses no stale anchor */ }
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
        let displays = FakeDisplayProvider.notchOnly()
        let hosts = IslandHosts(provider: displays)                    // as AppDelegate builds it: hosts pre-warmed (D-N8, D-N9)
        let hud = NotchHUD(hosts: hosts, provider: displays)
        let snapshot = try HUDFx.snapshot(submitted: 1)
        let start = ContinuousClock.now                                 // the clock starts before prepare and show
        hud.prepare(near: CGPoint(x: -4500, y: -4500))
        hud.show(snapshot)
        let host = try #require(hosts.host(on: 1))
        #expect(host.isVisible)                                         // a panel on screen, not only machine state
        #expect(host.frame == IslandLayout.frame(.collapsed, on: displays.displays[0]).cgRect)
        #expect(ContinuousClock.now - start < .milliseconds(50))
    }
}

@Suite("Island ink (D-N10, NFR-14 ≥ 4.5:1, non-text ≥ 3:1)")
struct NotchInkTests {
    @Test func whiteAndSecondaryTextOnBlackPassWithMargin() {
        #expect(NotchInk.contrast(textOpacity: 1) > 20)
        #expect(NotchInk.contrast(textOpacity: NotchInk.secondaryOpacity) >= 4.5)
    }

    @Test func theRingMeetsNonTextContrast() {                       // WCAG 1.4.11, design/19 §5.5
        #expect(NotchInk.contrast(textOpacity: NotchInk.ringTrackOpacity) >= 3)
        #expect(NotchInk.contrast(fill: 1, track: NotchInk.ringTrackOpacity) >= 3)
    }
}
```

`FakeDisplayProvider` lives in `Tests/ZivletUITests/` and places every display off screen. Every test builds its
`IslandHosts` on it and passes it in, as the app does. `NotchInk.contrast`
reuses `HUDInk.luminance`.

RED: `cannot find 'NotchHUD'`. GREEN: `swift test --filter "NotchHUD|NotchInk|ResultCard|ActionHUD"`, `make app`.

Commit `feat(ui): Notch HUD shows progress, results and action toasts on the island`.

---

## Task N11 — Settings › General row, batch routes and app wiring (design/19 §5.1, §5.4, §6, §7; D-M5a-2, D-M5a-6, D-M5a-8 … D-M5a-10)

| Field | Value |
|---|---|
| Goal | **Settings:** a "Progress and results" (*new*) section in `GeneralPane` with the picker "Show progress and results:" (*new*) offering "At the notch" (*new*; "At the top of the screen" (*new*) on a Mac without a built-in notch) and "Near the drop" (*new*, OP-2); the selection shows `placement.resolved(hasBuiltInNotch:)`; choosing stores the explicit value. The label strings are constants in `PlacementCopy`. `SettingsModel` gets `hasBuiltInNotch` from the provider's latch (design/19 §3.2) and follows it through its own `changes` stream. **Composition root:** `AppDelegate` builds one `ScreenGeometryReader` and one `IslandHosts`, then one `NotchHUD(hosts:provider:)`, and gives the same `NotchHUD` to `ConversionWiring` and `ActionWiring` (M5b's tray registers with the same `IslandHosts`). **Batch routes:** pure `BatchRoutes` in `ZivletUI` (it replaces the planned `PresenterRouter`, whose job `HUDPlacement.resolved` already does): `enqueuing(point:, at:, route:)` at each drop, `claiming(_ batch:)` on the first snapshot of an unknown `BatchID` (pops the oldest pending route; with none pending, the default route), `route(of:)` for every later snapshot, `retrying(_ source:, anchor:)` (enqueues the source's route with the new anchor), `forgetting(_:)` when a batch closes. `ConversionWiring.present` claims or looks up the route and only then calls the routed presenter's `prepare(near:)` (once, on claim) and `show`; Retry from either presenter arrives as `onRetry(batch, anchor)` and goes through `retrying` before `conversions.retry`. `ActionWiring` resolves the route at `run` time (it has the point and the result together) and `announce` (status-menu undo, no drop) uses the default route. Default route = `(override ?? settings.hud.placement).resolved(hasBuiltInNotch:)`. **Override:** `SettingsWiring` reads `-ZivletHUDPlacement notch|nearDrop` as it reads `-ZivletRevealResults`; `SettingsStore` never sees it. **Status menu:** "Show Progress and Results" (*new*, D-N12), enabled while the island has items, sends `expandRequested` to `IslandHosts`. **Wheel:** the app's wheel wiring sends `wheelShown` / `wheelHidden` to `IslandHosts`. **Accessibility settings:** observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and forward `reduceMotionChanged`; observe `NSWorkspace.isVoiceOverEnabled` and `isSwitchControlEnabled` (key-value observation) and set the board's `assistiveTech`. **Logging:** `Island: <surface>` and `Island: frame <x> <y> <w> <h>` notice lines (surface names and whole numbers only, public) after each applied surface, for the demo; file names stay private as today |
| Acceptance | tests below green; `make app`; manual: `make convert-demo FILE=… TO=jpeg PLACEMENT=notch` shows the island and logs both `Island:` lines, `PLACEMENT=nearDrop` today's card |
| Effort | M (2 days; it was S before batch routes, the menu command and the shared hosts were added) |

**Files:** create `Sources/ZivletUI/Notch/BatchRoutes.swift`, `Sources/ZivletUI/Notch/PlacementOverride.swift`,
`Sources/ZivletUI/Settings/PlacementCopy.swift`,
`Tests/ZivletUITests/BatchRoutesTests.swift`, `Tests/ZivletUITests/PlacementSettingsTests.swift`; modify
`Sources/ZivletUI/Settings/GeneralPane.swift`, `Sources/ZivletUI/Settings/SettingsModel.swift`,
`App/ConversionWiring.swift`, `App/ActionWiring.swift`, `App/AppDelegate.swift` (build `ScreenGeometryReader`,
`IslandHosts`, the one `NotchHUD`), `App/StatusMenu.swift` and `App/MenuWiring.swift` (the menu command), the wheel
wiring file that shows and hides the wheel, `App/SettingsWiring.swift` (the override), `Scripts/demo-convert.sh`
(optional 4th argument → `-ZivletHUDPlacement`), `Makefile` (`PLACEMENT` passed through).

### N11.1 Failing tests first

```swift
@Suite("Batch routes (D-M5a-2, D-M5a-8)")
struct BatchRoutesTests {
    let notch = BatchRoutes.Route.notch, card = BatchRoutes.Route.nearDrop

    @Test func twoQuickDropsWithDifferentPlacementsKeepTheirOwnRoutes() {
        let a = BatchID(), b = BatchID()
        var routes = BatchRoutes(defaultRoute: notch)
            .enqueuing(point: CGPoint(x: 10, y: 10), at: .seconds(1), route: notch)
            .enqueuing(point: CGPoint(x: 50, y: 50), at: .seconds(2), route: card)  // setting changed in between
        let first: BatchRoutes.Claim
        (routes, first) = routes.claiming(a)
        let second: BatchRoutes.Claim
        (routes, second) = routes.claiming(b)
        #expect(first.route == notch && second.route == card)
        #expect(routes.route(of: a) == notch && routes.route(of: b) == card)
    }

    @Test func aRetryFromEitherPresenterKeepsTheSourceRoute() { /* claim a (card), retrying(a, anchor: p), claim c → card, point p */ }
    @Test func aBatchNobodyPreparedTakesTheDefaultRoute() { /* claim with nothing pending → defaultRoute, point nil */ }
    @Test func aLaterSnapshotNeverConsumesAPendingRoute() { /* claim a, enqueue, route(of: a) → unchanged queue */ }
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

    @Test func withTheLidClosedTheLabelStaysAtTheNotch() { /* provider: only the external display, latch true → "At the notch" */ }
}
```

The app target has no unit-test bundle, so the override's logic is a pure helper in `ZivletUI`,
`PlacementOverride.parse(_ arguments: [String: String]) -> HUDPlacement?` and
`PlacementOverride.defaultRoute(override:settings:hasBuiltInNotch:)`, which `SettingsWiring` calls. Its test,
`theLaunchArgumentOverridesForOneRunAndIsNotStored`, sits in `PlacementSettingsTests`: the default route follows the
override, a `SettingsStore` on a private suite keeps `current.hud.placement` and `diagnosticsJSON` unchanged, and
choosing the value equal to the override is saved. The wiring itself is checked by the
announce and retry cases in the manual demo and by `BatchRoutesTests`, which carry the logic; `ConversionWiring` only
calls them. Plus the existing `SettingsPaneSnapshotTests` gains one snapshot of the General pane with the new section.

RED: `cannot find 'BatchRoutes'`. GREEN: `swift test --filter "BatchRoutes|PlacementSettings|SettingsPane"`,
`make app`, then the two manual demos (quit the app afterwards with `osascript -e 'quit app "Zivlet"'`).

Commits `feat(ui): Settings choice for where progress and results show`,
`feat(ui): batch routes so each batch stays with the presenter its drop chose`, and
`feat(app): one island for the HUD, routing per drop, and Show Progress and Results in the status menu`.

---

## Task N12 — Display geometry in Copy Diagnostics (design/19 §3.3; OP-5)

| Field | Value |
|---|---|
| Goal | `DisplayGeometry.diagnosticsLine` (pure, `ZivletNotchCore`): "display 1: frame 0 0 1800 1169 · visible 0 94 1800 1036 · safe top 38 · aux left 0 1131 790 38 · aux right 1010 1131 790 38 · housing 790 1131 220 38 · built in" (*new* format, no names). `DiagnosticsSources` gains `displays: [String]` and `Diagnostics.build` prints a "Displays" section, ending with the line "built-in notch seen: yes" or "no" (the design/19 §3.2 latch); the app fills it from `ScreenGeometryReader`. Each display line ends "· built in" for the built-in display |
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
            "display 1: frame 0 0 1800 1169 · visible 0 94 1800 1036 · safe top 38 · aux left 0 1131 790 38 · aux right 1010 1131 790 38 · housing 790 1131 220 38 · built in")
    }

    @Test func aDisplayWithoutANotchSaysSo() throws {
        #expect(try DisplayFixtures.noNotch1080().diagnosticsLine.hasSuffix("· housing none"))   // not built in: no suffix
    }
}
```

RED: `value of type 'DisplayGeometry' has no member 'diagnosticsLine'`. GREEN: both suites.

Commit `feat(ui): display geometry in Copy Diagnostics so notch sizes can be recorded`.

---

## Task N13 — QA list, exit runner, idle-CPU sampler, exit run and record

| Field | Value |
|---|---|
| Goal | `docs/plan/qa/notch.md`: owner rows Q1–Q22 from design/19 §10, each with steps, expected result and a result column. `Scripts/idle-cpu.sh PID SECONDS` (samples `ps -o time=` at start and end, prints CPU % with three decimals; exits 2 on a missing process; refuses fewer than 120 s, because `ps` counts CPU time in 10 ms steps and 10 ms over 120 s is 0.008 %, well under the 0.1 % gates of X6). `Scripts/m5a-exit.sh` with rows X1–X7 of the index §6, logs in `build/m5a-exit/`, the same structure as `Scripts/m4-exit.sh` (row list, `--row Xn`, summary table); the TCC row counts tccd requests with `preflight=no` attributed to Zivlet and lists the preflight checks separately (D-M5a-5). `make notch-demo` runs the conversion demo with the notch placement and captures the island region with `screencapture -x -R` from the `Island: frame x y w h` notice line that N11 logs. The X6 row launches the Debug app five times, each with one state (`-ZivletHUDPlacement nearDrop` and no job for the baseline; `-ZivletHUDPlacement notch` and no job for "hidden"; then `-ZivletIslandPreview collapsed`, `progress` and `indeterminate`), waits 10 s, samples 120 s, and gates on the difference from the baseline. `make m5a-exit`. Then run it and write `docs/plan/13-m5a-record.md` (contents, commits, gates, decisions, gaps, owner steps), honest about every row that did not pass or was not run |
| Acceptance | `Scripts/tests/test-m5a-exit.sh` and `Scripts/tests/test-idle-cpu.sh` pass under `make script-test` (rows stubbed, as `test-m4-exit.sh` does); `make m5a-exit` run once with its results in the record |
| Effort | S |

**Files:** create `docs/plan/qa/notch.md`, `Scripts/idle-cpu.sh`, `Scripts/m5a-exit.sh`, `Scripts/demo-notch.sh`,
`Scripts/tests/test-m5a-exit.sh`, `Scripts/tests/test-idle-cpu.sh`, `docs/plan/13-m5a-record.md`; modify `Makefile`.

### N13.1 Failing tests first

`Scripts/tests/test-idle-cpu.sh`: a stub `ps` on `PATH` that prints `0:01.00` then `0:01.12` → the script prints
`0.100` for 120 s; 60 s → exit 2 with "sample at least 120 s"; a missing PID → exit 2 with "no process". `Scripts/tests/test-m5a-exit.sh`: with every row command
stubbed to succeed, the summary lists X1–X7 as pass; with the TCC stub returning one `preflight=no` line for Zivlet,
X5 fails; with only `preflight=yes` lines, X5 passes and lists them.

RED: `Scripts/idle-cpu.sh: No such file or directory`. GREEN: `make script-test`.

Commits `test(scripts): M5a exit runner, idle-CPU sampler and the notch demo`,
`docs: owner QA list for the notch island and the Notch HUD`, and after the run
`docs: M5a record: notch island core and Notch HUD`.

---

## After N13

The owner reviews the commits and the record, runs `docs/plan/qa/notch.md` on real hardware (an external display,
full screen, Stage Manager, VoiceOver, a crowded menu bar), and answers OP-1 … OP-6 (index §7). M5b starts with NB1
(index §9).

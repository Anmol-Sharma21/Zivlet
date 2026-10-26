# 18a — M6 Stream A: the M5b follow-ups (G-M5b-8, G-M5b-9, G-M5b-10)

Part of [18-implementation-plan-m6](18-implementation-plan-m6.md). Conventions: index §6. Gaps:
[17-m5b-record](17-m5b-record.md) §7. Look and words: [design/19c](../design/19c-drop-box-look.md) §3.5, §4.1, §5,
D-BL12. Swift below is specification-grade and was not compiled.

The box already draws the busy state (verb, bar, percent, Cancel) and maps Esc to `.cancelBusy`; nothing drives
it, and nothing it would cancel listens. This stream makes the long bulk actions — Move to…, Copy to…, Move to
Trash — report progress per item, stop between items when cancelled, return a correct partial result with Undo, and
run off the main thread. It also adds the panel's opacity exit.

New strings (*new*, Zivlet's own, few words): busy verbs "Moving 12 items", "Copying 12 items", "Moving 12 items to
the Trash"; partial titles "Stopped. 7 items weren't moved.", "Stopped. 7 items weren't copied.", "Stopped. 7 items
are still here.". The existing toast `BoxCopy.trashed` ("Moved 3 to the Trash") is kept.

---

## Task A0 — Baseline

| Field | Value |
|---|---|
| Goal | Record the starting point on `m6`: `nice -n 10 make test lint coverage app` |
| Acceptance | every gate green, or each failure named; a timing failure rerun once by name (G-M6-9 is known: `SubprocessRunnerTests.aChildIgnoringSIGINTIsKilledAfterTheGrace` failed once at 0.41 s and passed on rerun) |
| Effort | S |

No commit unless something has to be fixed; a fix gets its own `fix(...)` commit with a test seen to fail first.

---

## Task A1 — `MoveExecutor` reports progress and stops between items

| Field | Value |
|---|---|
| Goal | `MoveExecutor.run(_ plan:, progress:)` calls `progress(done, total)` after each step and checks `Task.isCancelled` **before** each step. A cancelled run returns a `MoveReport` whose new `cancelled: [URL]` lists the steps not started; steps already done stay done (a cross-volume copy in progress finishes its item: the check is between items, never inside one, so no half copy is left) |
| Acceptance | fake copy that sleeps per item: cancel after the 3rd of 10 → `moved.count == 3`, `cancelled.count == 7`, no hidden `.zivlet-move-*` left; progress calls are `(1,10)…(3,10)` in order; an uncancelled run reports `(10,10)` last and `cancelled` empty; existing `MoveExecutorTests` stay green |
| Effort | S |

**Files:** modify `Sources/ZivletActions/MoveExecutor.swift`, `Sources/ZivletActions/MoveReport.swift`
(`cancelled`, default `[]`); tests in `Tests/ZivletActionsTests/MoveExecutorTests.swift`.

```swift
@Test func aCancelledRunStopsBetweenItemsAndListsTheRest() async throws {
    let dir = try TempDir()
    let plan = try MoveFixtures.crossVolumePlan(items: 10, in: dir)
    let gate = StepGate(pauseAfter: 3)                       // the fake copy waits after item 3
    let executor = MoveExecutor(copy: gate.copy, trash: { _ in })
    let task = Task { await executor.run(plan, progress: { done, total in gate.record(done, total) }) }
    await gate.reachedPause()
    task.cancel()
    gate.resume()
    let report = await task.value
    #expect(report.moved.count == 3 && report.cancelled.count == 7)
    #expect(try dir.hiddenMoveFolders().isEmpty)
    #expect(gate.progress == [(1, 10), (2, 10), (3, 10)])
}
```

RED: `extra argument 'progress' in call`. Commit `feat(actions): Move and Copy to report progress and stop between
items`.

---

## Task A2 — The box's busy overlay for Move to… and Copy to…

| Field | Value |
|---|---|
| Goal | `ActionService.moveReporting(_:progress:)` / `copyReporting(_:progress:)` pass a `TransferProgress` port to the executor with `started(count:)` (called after the folder is chosen and the plan made, so the overlay never covers the chooser) and `advanced(done:total:)`. `BoxController.moveItems()` / `copyItemsTo()` send `.busyStarted(verb:)` on start, `.progress(done/total)` per item (main actor, coalesced to ≥ 50 ms apart), `.busyEnded` at the end, always, also on cancel and failure. Cancel and Esc already cancel `running`; the result for a cancelled run is `.partial` with the *new* "Stopped." card and Undo for the part that moved; nothing moved → `.cancelled` (silent, as today) |
| Acceptance | `BoxRig` with a fake executor gate: Move of 12 → presentation shows `.busy("Moving 12 items", 0)`, then fractions up to 3/12; Esc → `running` cancelled; result `.partial(toast: "Moved 3 items", card: "Stopped. 9 items weren't moved.", undo: batch)`; overlay gone; the moved 3 items point at their new paths (existing `follow`); Undo of the batch moves the 3 back (existing `UndoHistory` path); Copy to… the same with copy words; a cancelled folder choice never shows the overlay |
| Effort | S |

**Files:** modify `Sources/ZivletActions/ActionService.swift` (`TransferProgress`, the two reporting functions,
`result` for `cancelled`), `Sources/ZivletActions/MoveReport.swift` (card lines for cancelled items),
`Sources/ZivletBox/BoxController+Bulk.swift`, `Sources/ZivletBox/BoxCopy.swift`; tests
`Tests/ZivletActionsTests/ActionServiceTests.swift`, `Tests/ZivletBoxTests/BoxMoveTests.swift`.

```swift
@Test func escapeStopsAMoveAndKeepsUndoForThePartThatMoved() async throws {
    let rig = try BoxRig(items: 12, executor: .pausing(after: 3))
    rig.controller.moveItems()
    try await rig.waitForOverlay(.busy(verb: "Moving 12 items", fraction: 0.25))
    rig.controller.apply(.escape)
    let result = try await rig.nextResult()
    #expect(result.toast == "Moved 3 items")
    #expect(result.card?.title == "Stopped. 9 items weren't moved.")
    #expect(result.undo != nil && rig.controller.presentation.overlay == nil)
}
```

RED: `extra argument 'progress' in call` in `ActionServiceTests`, then the overlay wait times out in `BoxMoveTests`.
Commit `feat(box): drive the busy overlay from Move to and Copy to, with Cancel and Esc`.

---

## Task A3 — Move to Trash: off the main thread, cancellable, with Undo

| Field | Value |
|---|---|
| Goal | `Trashing.trash(_:) throws(ShelfError) -> URL` returns the item's place in the Trash (`FileManager.trashItem(at:resultingItemURL:)`). A new `BoxTrasher` (`nonisolated`, `@concurrent func run(_ targets: BulkTargets, progress:) async -> TrashReport`) trashes item by item, checks cancellation before each, and returns `trashed: [(id, original, inTrash, stamp)]`, `failed: [String]`, `cancelled: [UUID]`. `BoxController.trash(_:)` becomes `runBulk { … }` with `.busyStarted("Moving n items to the Trash")` only when n > 1 (one item stays instant, as today), applies the report to the **current** library by id (items removed meanwhile are skipped, R11), records an `UndoMove` batch (original ← in Trash) through a new `BoxPorts.recordUndo` closure the app wires to `UndoHistory.record(_:moves:)`, and reports `.done(toast:, undo: batch)` or `.partial` with "Stopped. n items are still here." |
| Undo | `AppDelegate.undo(_:)` asks `box.controller.undoTrash(batch)` first: if the batch is a box trash it re-adds the items (same ids, old bookmarks, in their old order, like `undoClear`) **after** `undoHistory.undo(batch)` moved the files back; items whose file could not come back stay out and are listed by the existing undo result |
| Acceptance | fake `Trashing` with a pause: 200 items, cancel at 50 → 50 trashed, 150 still in the box, toast + "Stopped." card, Undo restores 50 files and 50 items in order; the main actor is never blocked: a probe task on the main actor runs while the fake trasher is paused; one item → no overlay; a refused item → listed, the rest go on |
| Effort | M |

**Files:** modify `Sources/ZivletShelfCore/Trashing.swift`, create `Sources/ZivletBox/BoxTrasher.swift`,
modify `Sources/ZivletBox/BoxController+Commands.swift`, `Sources/ZivletBox/BoxPorts.swift` (`recordUndo`),
`Sources/ZivletBox/BoxController.swift` (`undoTrash`, pending trash batches), `App/BoxWiring.swift`,
`App/AppDelegate.swift` (`undo`); tests create `Tests/ZivletBoxTests/BoxTrashTests.swift`, update the fakes in
`Tests/ZivletBoxTests/BoxBulkFakes.swift`.

```swift
@Test func aCancelledTrashKeepsTheRestAndUndoBringsBackWhatWent() async throws {
    let rig = try BoxRig(items: 200, trash: .pausing(after: 50))
    rig.controller.trash(rig.controller.bulkTargets())
    try await rig.trash.reachedPause()
    #expect(await rig.mainActorIsResponsive())
    rig.controller.apply(.escape)
    let result = try await rig.nextResult()
    #expect(rig.controller.current?.items.count == 150)
    #expect(result.card?.title == "Stopped. 150 items are still here.")
    let undone = await rig.undo(result.undo!)
    #expect(undone.restored.count == 50 && rig.controller.current?.items.count == 200)
}
```

RED: `cannot find 'BoxTrasher' in scope`. Commits `feat(shelf): the Trash port returns where the item went`,
`feat(box): trash items off the main thread, cancellably, with Undo`.

---

## Task A4 — Resolve at show and promise intake off the main thread

| Field | Value |
|---|---|
| Goal | `Shelf.resolving(…)` is pure and stays as it is; the controller calls it through a `@concurrent` helper `BoxResolver.resolve(_ shelf:, ports:) async -> ResolvedShelf`. On show the panel draws at once with the last known statuses (or "present" for never-resolved items), then applies the resolved shelf when it arrives **if the box is still the same box and its item ids are unchanged** (otherwise it resolves again). Promise files: `PromiseReceiving` hands the received file URLs to a `@concurrent` item maker; the controller adds the made items on the main actor |
| Acceptance | a fake resolver that blocks until released: `show()` returns and renders before the resolver finishes; after release, missing items turn grey; an item removed while resolving is not brought back; a promise of 20 files becomes 20 items without the main actor waiting on the maker (probe task runs while the fake maker is paused); `BoxRestoreTests`, `PromiseCollectorTests` stay green |
| Effort | S |

**Files:** create `Sources/ZivletBox/BoxResolver.swift`, modify `Sources/ZivletBox/BoxController+Panel.swift`,
`Sources/ZivletBox/BoxController+Storage.swift`, `Sources/ZivletBox/PromiseReceiving.swift`,
`Sources/ZivletBox/BoxController+Intake.swift`; tests create `Tests/ZivletBoxTests/BoxResolveTests.swift`, extend
`Tests/ZivletBoxTests/PromiseCollectorTests.swift`.

```swift
@Test func showDrawsBeforeResolvingAndAppliesTheResultAfter() async throws {
    let rig = try BoxRig(items: 3, missing: 1, resolver: .blocking)
    rig.controller.show()
    #expect(rig.controller.renders == 1 && rig.controller.statuses.values.allSatisfy(\.isAvailable))
    rig.resolver.release()
    try await rig.waitFor { rig.controller.viewModel.missingCount == 1 }
}
```

RED: the first expectation fails (today `show()` resolves before it renders, so the missing item is already grey).
Commit `perf(box): resolve the box and make promise items off the main thread`.

---

## Task A5 — The panel leaves with opacity (D-BL12)

| Field | Value |
|---|---|
| Goal | When `render()` finds no frame for the presentation, the controller asks a `PanelFading` port to fade the panel's `alphaValue` to 0 and orders it out in the completion. Curve: `IslandMotion(reduceMotion:).collapse` mapped through `IslandAnimation.timing(for:)` (spring settle, at most 0.6 s); under Reduce Motion `.fade(0.18)` (D-M6-3, OS-M6-6). A show that arrives during the fade cancels it and sets alpha back to 1 before ordering front. Tests use an instant fader; the app uses `NSAnimationContext` with `allowsImplicitAnimation` |
| Acceptance | with a recording fader: hide → one `fadeOut(duration:)` with the collapse settle time, panel still visible until completion, then ordered out; Reduce Motion → 0.18 s; show during the fade → `cancel()` then alpha 1 and visible; `BoxPanelTests` stay green; the box-states demo (Y5) still captures every state |
| Effort | S |

**Files:** create `Sources/ZivletBox/PanelFading.swift` (port + `SystemPanelFader`), modify
`Sources/ZivletBox/BoxController+Panel.swift`, `Sources/ZivletBox/BoxPorts.swift`; tests create
`Tests/ZivletBoxTests/BoxExitTests.swift`.

```swift
@Test func hidingFadesBeforeOrderingOut() throws {
    let fader = RecordingFader()
    let rig = try BoxRig(items: 2, fader: fader, reduceMotion: false)
    rig.controller.show()
    rig.controller.apply(.hide)
    #expect(fader.fades == [IslandAnimation.motion.timing(for: IslandMotion(reduceMotion: false).collapse).seconds])
    #expect(rig.panel.isVisible)
    fader.finish()
    #expect(!rig.panel.isVisible)
}
```

RED: `cannot find 'RecordingFader' in scope`, then `fades` is empty (the panel orders out at once). Commit
`feat(box): fade the Drop Box out instead of removing it at once`.

---

## Stream A checks before Stream B

`nice -n 10 make test lint coverage app`; `Scripts/m5b-exit.sh --only Y4,Y5` (the box demo and every state still
work). Update `docs/plan/qa/drop-box.md` with the rows for busy, cancel and Undo (E1 lists them).

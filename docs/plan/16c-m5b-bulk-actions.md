# 16c — M5b Stream C: bulk actions (NB4)

Part of [16-implementation-plan-m5b](16-implementation-plan-m5b.md). Conventions: index §6. Behaviour:
[design/17e-app](../design/17e-app.md) §2.3 "Bulk actions"; look and words: [design/19c](../design/19c-drop-box-look.md)
§3.5, §4.1, §5. Acceptance: 05 row P2-142. **Zip is deferred** (D-M5b-11, G-M5b-1): P2-111 EngineArchive is not
built. Swift below is specification-grade and was not compiled.

Results of every bulk action go where every action's result goes today: the action toast or card at the notch or
near the drop, by the placement setting (D-M5a-3). `ZivletBox` cannot import `ZivletUI`, so the controller hands an
`ActionResult` (and the panel's frame as the anchor) to a closure that `App/BoxWiring.swift` forwards to the
`ActionPresenter` the action wiring already picks.

---

## Task C1 — `BulkTargets`: the selection or every item; unavailable items as failures

| Field | Value |
|---|---|
| Goal | Pure `BulkTargets.resolve(selection:in:statuses:) -> BulkTargets { urls: [URL], ids: [UUID], failures: [String] }` in `ZivletShelfCore`. An empty selection means every item. Items that are missing, in the Trash or on a volume that is not connected are left out and named in `failures` (*new*): "photo.heic is missing.", "photo.heic is in the Trash.", "a.mov is on Backup, which isn't connected." |
| Acceptance | tests for an empty selection, a partial selection, and each status; order follows the box |
| Effort | S |

**Files:** create `Sources/ZivletShelfCore/BulkTargets.swift`, `Tests/ZivletShelfCoreTests/BulkTargetsTests.swift`.

```swift
@Suite("Bulk targets (P2-142: selection, or all; per-item failures)")
struct BulkTargetsTests {
    @Test func noSelectionMeansEveryPresentItem() throws {
        let (shelf, statuses) = try ShelfFixtures.box(present: 3, missing: 1)
        let targets = BulkTargets.resolve(selection: [], in: shelf, statuses: statuses)
        #expect(targets.urls.count == 3 && targets.failures == ["d.txt is missing."])
    }
}
```

RED: `cannot find 'BulkTargets' in scope`. Commit `feat(shelf): choose bulk-action targets and name what cannot
take part`.

---

## Task C2 — Share picker (prototype §3.4)

| Field | Value |
|---|---|
| Goal | `SharePicking` port in `ZivletActions` (`show(_ urls:, relativeTo view:, edge:)`) and `SystemSharePicker` using `NSSharingServicePicker(items:)` with a delegate, anchored to the Share button; the deprecated `NSSharingService.sharingServices(forItems:)` is not used (warnings are errors, so a use fails the build). The panel calls it with the bulk targets; no toast (the system reports nothing useful) |
| Acceptance | with a fake picker: Share shows it once with the targets and the button as anchor; with no present items, Share shows the failure card instead |
| Effort | S |

**Files:** create `Sources/ZivletActions/SharePicking.swift`, `Tests/ZivletActionsTests/SharePickerTests.swift`;
modify `Sources/ZivletBox/BoxController.swift` (command `.share`), `Tests/ZivletBoxTests/BoxControllerTests.swift`.

RED: `cannot find 'SharePicking' in scope`. Commit `feat(actions): share the Drop Box's items with the system share
picker`.

---

## Task C3 — AirDrop, Copy, Copy Paths from the box

| Field | Value |
|---|---|
| Goal | `BoxActions` in `ZivletBox` runs the existing `AirDropAction.send`, `ClipboardAction.copyItems` and `ClipboardAction.copyPaths(shellQuoted:)` (⌥ for the quoted form, as the Copy Path slice) on `BulkTargets.urls`, waits one run-loop turn before AirDrop's sheet (as `ActionService` does), and returns their `ActionResult` with `failures` appended as card lines |
| Acceptance | with the existing fakes (`SharingService`, a private pasteboard): 200 URLs reach the clipboard (prototype §3.4 wrote and read back 200); failures appear as lines; AirDrop unavailable → the existing card |
| Effort | S |

**Files:** create `Sources/ZivletBox/BoxActions.swift`, `Tests/ZivletBoxTests/BoxActionsTests.swift`.

RED: `cannot find 'BoxActions' in scope`. Commit `feat(box): AirDrop, Copy and Copy Paths for the whole box`.

---

## Task C4 — Move to…; box references follow the files

| Field | Value |
|---|---|
| Goal | Expose the Move action's path for callers that need the report: `ActionService.moveReporting(_ urls:) async -> (ActionResult, MoveReport?)` (folder chooser, plan, executor, one undo entry, today's toasts "Moved 12 items" with Undo). `BoxActions.move` calls it; then `Shelf.relocating(_ moves: [String: String], bookmarks:)` updates `lastKnownPath` and bookmarks of the moved items at once (their bookmarks would follow anyway: prototype §3.5) and saves. Items that failed stay where they were and are listed |
| Acceptance | with fake folders and executor: one undo batch for the whole selection; moved items carry their new paths; a cancelled folder choice changes nothing; the existing `ActionServiceTests` for `.moveTo` stay green |
| Effort | S |

**Files:** modify `Sources/ZivletActions/ActionService.swift`, `Sources/ZivletBox/BoxActions.swift`,
`Sources/ZivletShelfCore/Shelf.swift` (`relocating`); tests `Tests/ZivletActionsTests/ActionServiceTests.swift`,
`Tests/ZivletBoxTests/BoxActionsTests.swift`, `Tests/ZivletShelfCoreTests/ShelfTests.swift`.

RED: `value of type 'ActionService' has no member 'moveReporting'`. Commit `feat(box): move the box's items to a
folder with one undo`.

---

## Task C5 — Copy to…: a copy mode and its undo (D-M5b-13)

| Field | Value |
|---|---|
| Goal | `MovePlan` gains `mode: .move \| .copy`. In copy mode `MoveExecutor` copies every item (same volume too) into a hidden `.zivlet-move-<id>` in the destination, checks size and item count, claims the name exclusively (`name 2` on a clash, including a copy into the item's own folder), and never trashes the original. `UndoLog` schema 2 adds `UndoCopy { copy: URL, stamp: FileStamp }` to a batch; a schema-1 `undo.json` decodes with no copies; undoing a copy batch puts each copy whose stamp is unchanged in the Trash and reports changed ones ("photo 2.heic changed since it was copied, so it was kept.", *new*). `ActionService.copyReporting(_:)` mirrors C4; toast "Copied 12 items" (*new*) with Undo |
| Acceptance | executor tests on `TempDir` (same folder → "a 2.txt", original untouched, a failed verification removes the hidden copy); `UndoLogTests` decode a schema-1 fixture and round-trip schema 2; undo trashes unchanged copies through a fake trash and keeps a changed one |
| Effort | M |

**Files:** modify `Sources/ZivletActions/MovePlanner.swift`, `MoveExecutor.swift`, `MoveSurvey.swift`,
`ActionService.swift`, `Sources/ZivletRuntime/UndoLog.swift`, `UndoHistory.swift`, `UndoResult.swift`; create
`Sources/ZivletRuntime/UndoCopy.swift`; tests `Tests/ZivletActionsTests/MoveExecutorTests.swift`,
`MovePlannerTests.swift`, `Tests/ZivletRuntimeTests/UndoLogTests.swift`, `UndoMoveTests.swift`, a schema-1 fixture
string in `UndoLogTests`.

```swift
@Test func copyIntoTheSameFolderKeepsTheOriginalAndNamesTheCopy() async throws {
    let dir = try TempDir()
    let file = try dir.file("a.txt", "x")
    let plan = try MoveSurvey().plan(items: [file], destination: dir.url, mode: .copy)
    let report = await MoveExecutor().run(plan)
    #expect(report.moved.map(\.target.lastPathComponent) == ["a 2.txt"])
    #expect(FileManager.default.fileExists(atPath: file.path))
}
```

RED: `extra argument 'mode' in call`. Commits `feat(runtime): undo a batch of copies` and `feat(actions): copy the
box's items to a folder with one undo`.

---

## Task C6 — Remove, Move to Trash, Clear, Locate…, Remove missing (D-M5b-12, D-M5b-21)

| Field | Value |
|---|---|
| Goal | Commands on the controller. **Remove** (⌫): drops the references; an owned copy's file goes to the Trash through the `Trashing` port. **Move to Trash** (⌘⌫): one item at once; more than one asks first with the inline confirm line (19c D-BL9; no alert); toast "Moved 3 to the Trash" (*new*); the items leave the box. **Clear**: inline confirm, then every reference goes; owned copies are trashed only after the 10 s undo window; toast "Cleared" with Undo for 10 s (`ActionResult.done(toast:undo:linger:)`, honoured by `ActionHUD` and `NotchHUD`). **Locate…** (one missing item): a `FileLocating` port (system: an open panel for one file) gives a new URL → new bookmark, item relocated. **Remove missing**: removes missing and in-Trash items; items on a volume that is not connected stay |
| Acceptance | controller tests with fakes for each command; the confirm overlay appears for 2+ items and not for 1; Escape answers "no"; Clear's undo within 10 s restores the box and trashes nothing; after 10 s the owned copies are trashed; the presenters' linger tests cover a 10 s toast; no `NSAlert` in `ZivletBox` (also Y9) |
| Effort | M |

**Files:** create `Sources/ZivletBox/BoxController+Commands.swift`, `Sources/ZivletBox/FileLocating.swift`; modify
`Sources/ZivletActions/ActionResult.swift`, `Sources/ZivletUI/HUD/ActionHUD.swift`,
`Sources/ZivletUI/Notch/NotchHUDBoard.swift` (action-toast linger from the result); tests
`Tests/ZivletBoxTests/BoxCommandTests.swift`, `Tests/ZivletUITests/ActionHUDTests.swift`,
`Tests/ZivletUITests/NotchHUDTimingTests.swift` (one case).

```swift
@Test func clearCanBeUndoneForTenSeconds() async throws {
    let rig = try BoxRig(items: 3, owned: 1)
    rig.controller.perform(.clear)
    rig.controller.confirm(true)
    #expect(rig.controller.library.current?.items.isEmpty == true && rig.trash.calls.isEmpty)
    #expect(rig.results.last?.linger == .seconds(10))
    await rig.controller.undoClear()
    #expect(rig.controller.library.current?.items.count == 3)
}
```

RED: `type 'BoxCommand' has no member 'clear'`. Commits `feat(box): remove, trash, clear and locate items` and
`feat(ui): let an action toast stay for the undo window it offers`.

---

## Task C7 — Storage line, Empty Box Storage, auto-clear runs

| Field | Value |
|---|---|
| Goal | The overflow menu's first line reads "Box storage 1.2 GB" (*new*) and offers "Empty Box Storage" (*new*: removes owned items from every box and trashes their files, after the inline confirm). Over `StorageBudget.warnBytes` the overflow button carries a small dot and Settings › General shows the same line with the same button. Auto-clear runs the A6 plan: "after they leave the box" when a drag-out ends with an operation other than none (`FileDragSource` reports the operation) or a Move finishes; "after 24 hours" checked at launch and each time the box is shown (no timers, so no idle wake-ups) |
| Acceptance | controller tests with a fake owned storage and clock; the dot appears at 2 GB; a drag-out that ends with `.copy` clears the dragged items under "after they leave the box"; nothing clears with the policy off |
| Effort | S |

**Files:** create `Sources/ZivletBox/BoxController+Storage.swift`; modify `Sources/ZivletActions/FileDragSource.swift`
(report the ending operation), `Sources/ZivletBox/Views/BoxActionBar.swift`, `Sources/ZivletUI/Settings/GeneralPane.swift`;
tests `Tests/ZivletBoxTests/BoxStorageTests.swift`.

RED: `value of type 'BoxController' has no member 'storageLine'`. Commit `feat(box): show box storage, empty it,
and clear items automatically when asked`.

---

## Task C8 — Convert all: a drag from the box opens the wheel

| Field | Value |
|---|---|
| Goal | Prove the existing path: a drag that starts in the box writes file URLs on the drag pasteboard, so the trigger host's types-only check sees files and the wheel opens on the modifier for every item (17e §2.3 "Convert all…", design 14 §1 allows drags from Zivlet's own windows). No new code is expected; if the test finds a gap, fix it in this task |
| Acceptance | a test writes the drag source's items to a private pasteboard and checks the types `SystemInputReader` looks for are present; a `TriggerHostTests` case runs a live drag with that type set and a modifier edge and sees `.show`; QA row B13 checks it with a real drag |
| Effort | S |

**Files:** create `Tests/ZivletBoxTests/BoxConvertAllTests.swift`; modify
`Tests/ZivletTriggerHostTests/TriggerHostTests.swift` (one case).

Commit `test(box): a drag out of the box can open the wheel for every item`.

---

## Task C9 — Zip deferred (D-M5b-11, G-M5b-1)

| Field | Value |
|---|---|
| Goal | Make the deferral visible and tested: `BoxCommand.allCases` has no zip command and the action bar and overflow menu show no Zip item (neither enabled nor greyed). The record (E6) lists G-M5b-1 with its next step: add the command with P2-111 through the `ZivletUI` coordinator (R3: Actions must not import engines) |
| Acceptance | a test over `BoxCommand.allCases` and the overflow menu's items |
| Effort | S |

**Files:** create `Tests/ZivletBoxTests/BoxCommandListTests.swift`.

Commit `test(box): no Zip until EngineArchive exists`.

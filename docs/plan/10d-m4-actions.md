# 10d — M4 stream C: the five Phase 1 actions (Copy, Copy Path, AirDrop, Move, Terminal)

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6. Independent of streams A and
B; C7 touches `App/AppDelegate.swift` and should land after D1 if both run in parallel (merge point noted in the index).

New SwiftPM target `ZivletActions` (02 §6 table: shell module, pure path formatting and planning testable without
AppKit). It depends on `ZivletCore` and `ZivletRuntime` (for `UndoHistory` move entries); AppKit/Foundation side
effects sit behind small protocols so every planner is unit-tested. Added to `Scripts/coverage.sh` `GATED_MODULES`.

Copy rule for every user-facing sentence below: Zivlet's own wording, written for this plan (03b §7 column "Errors"
holds the agreed sentences; new ones are marked *new*).

---

## Task C1 — `ActionRequest`: local items only, de-duplicated, with the ⌥ state (P1-44 base)

| Field | Value |
|---|---|
| Goal | `ActionRequest(action:urls:optionHeld:)` validates at the boundary: every URL is a `file:` URL with a POSIX path that exists (`lstat`), standardized and de-duplicated in drop order; non-file or missing items are collected as `rejected` with a reason (`.notLocal`, `.missing`). An empty accepted list throws `ActionError.nothingLocal(action)`. `WheelSelection` gains `optionHeld: Bool`, read from `NSEvent.modifierFlags.contains(.option)` at drop (no permission needed) |
| 05 rows | P1-44, P1-45 (shared base) |
| Sources | 03b §7 ("Non-file URLs refused per action"), 10a §6 |

**Files:** modify `Packages/ZivletKit/Package.swift` (+ `ZivletActions`, `ZivletActionsTests`); create
`Sources/ZivletActions/ActionRequest.swift`, `Sources/ZivletActions/ActionError.swift`,
`Tests/ZivletActionsTests/ActionRequestTests.swift`; modify `Sources/ZivletWheelCore/WheelSelection.swift`,
`Sources/ZivletWheel/WheelController+Drop.swift` (fills `optionHeld`), `Tests/ZivletWheelTests/WheelControllerTests.swift`.

### C1.1 Failing tests first

```swift
import Foundation
import Testing
import ZivletCore

@testable import ZivletActions

@Suite("Action requests: local items only, de-duplicated (C1)")
struct ActionRequestTests {
    let dir = try! TempDir()

    @Test func keepsDropOrderAndRemovesDuplicates() throws {
        let a = try dir.file("a.txt"), b = try dir.file("b.txt")
        let request = try ActionRequest(action: .copyFilePath, urls: [a, b, a, URL(fileURLWithPath: a.path + "/.")],
            optionHeld: false)
        #expect(request.items == [a.standardizedFileURL, b.standardizedFileURL])
        #expect(request.rejected.isEmpty)
    }

    @Test func remoteAndMissingItemsAreRejectedWithAReason() throws {
        let a = try dir.file("a.txt")
        let request = try ActionRequest(action: .copyTo,
            urls: [a, URL(string: "https://example.com/x.png")!, dir.url.appending(path: "gone.txt")], optionHeld: false)
        #expect(request.items == [a.standardizedFileURL])
        #expect(request.rejected.map(\.reason) == [.notLocal, .missing])
    }

    @Test func nothingLocalThrows() {
        #expect(throws: ActionError.nothingLocal(.shareAirDrop)) {
            try ActionRequest(action: .shareAirDrop, urls: [URL(string: "https://example.com")!], optionHeld: false)
        }
    }

    @Test func foldersAreAllowed() throws {
        let sub = try dir.folder("sub")
        #expect(try ActionRequest(action: .openInTerminal, urls: [sub], optionHeld: false).items == [sub.standardizedFileURL])
    }

    @Test(arguments: ActionID.allCases)
    func everyActionHasUserCopyForNothingLocal(action: ActionID) {
        #expect(!ActionError.nothingLocal(action).userMessage.isEmpty)
    }
}
```

`TempDir` is a small helper added to `Tests/TestSupport` (create, `file(_:)`, `folder(_:)`, removal in `deinit`).

### C1.2 Run, expect failure

`swift test --filter ZivletActionsTests` → `error: no such module 'ZivletActions'` before the Package.swift change,
then `cannot find 'ActionRequest' in scope`.

### C1.3 Implement

User copy (`ActionError.userMessage`): `.copyTo` "Copy works only with items stored on this Mac.", `.copyFilePath`
"Paths can be copied only for items stored on this Mac.", `.shareAirDrop` "Zivlet couldn't start AirDrop for these
files.", `.moveTo` "Choose a folder on this Mac to move into." (for a bad destination) / "Only items stored on this Mac
can be moved." (*new*, for sources), `.openInTerminal` "Only folders on this Mac can be opened in a terminal." (*new*),
`.pinFloating` "Float arrives in a later version." (*new*; the petal is hidden anyway, C7).

### C1.4 Verify green / C1.5 Commit

`swift test --filter "ZivletActionsTests|ZivletWheelTests"`. Commit `feat(actions): validated action requests with
the Option-key state`.

---

## Task C2 — Copy and Copy Path (P1-44)

| Field | Value |
|---|---|
| Goal | `PathFormatter.lines(_:)` joins POSIX paths with `\n`; `PathFormatter.shell(_:)` single-quotes each path (`'` → `'\''`) and joins with spaces (03b §7 row 5). `ClipboardAction.copyItems` clears the pasteboard and writes the URLs as file URLs (`writeObjects([NSURL])`); `copyPaths` writes one `.string`. Result toast copy: "Copied 3 items" / "Copied 1 path" / "Copied 3 paths" (*new* pluralisation) |
| 05 rows | P1-44 |

**Files:** create `Sources/ZivletActions/PathFormatter.swift`, `Sources/ZivletActions/ClipboardAction.swift`,
`Tests/ZivletActionsTests/PathFormatterTests.swift`, `Tests/ZivletActionsTests/ClipboardActionTests.swift`.

### C2.1 Failing tests first

```swift
@Suite("Copy Path formatting (P1-44, 03b §7 row 5)")
struct PathFormatterTests {
    @Test func linesAreNewlineJoined() {
        let urls = ["/a/b.txt", "/c d/e.png"].map { URL(fileURLWithPath: $0) }
        #expect(PathFormatter.lines(urls) == "/a/b.txt\n/c d/e.png")
    }

    @Test(arguments: [
        ("/plain/file", "'/plain/file'"),
        ("/with space/x", "'/with space/x'"),
        ("/it's/here", #"'/it'\''s/here'"#),
        ("/$HOME/`x`/!", "'/$HOME/`x`/!'"),
        ("/new\nline", "'/new\nline'"),
    ])
    func shellQuotingSurvivesEveryMetacharacter(path: String, quoted: String) {
        #expect(PathFormatter.shell([URL(fileURLWithPath: path)]) == quoted)
    }

    @Test func shellVariantIsSpaceJoined() {
        #expect(PathFormatter.shell([URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b c")]) == "'/a' '/b c'")
    }

    @Test func quotedPathsRoundTripThroughTheShell() throws {
        let tricky = ["/tmp/it's", "/tmp/a b", "/tmp/$x", "/tmp/new\nline"].map { URL(fileURLWithPath: $0) }
        let echoed = try Shell.run("/bin/sh", ["-c", "for p in \(PathFormatter.shell(tricky)); do printf '%s\\0' \"$p\"; done"])
        #expect(echoed.split(separator: "\0").map(String.init) == tricky.map(\.path))
    }
}

@Suite("Copy and Copy Path write the pasteboard (P1-44)")
@MainActor
struct ClipboardActionTests {
    @Test func copyWritesFileURLs() throws {
        let board = NSPasteboard(name: .init("zivlet-test-\(UUID())")); defer { board.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/etc/hosts"), URL(fileURLWithPath: "/etc/shells")]
        let result = ClipboardAction(pasteboard: board).copyItems(urls)
        #expect((board.readObjects(forClasses: [NSURL.self]) as? [URL]) == urls)
        #expect(result.toast == "Copied 2 items")
    }

    @Test func copyPathWritesOneStringAndOptionQuotes() throws {
        let board = NSPasteboard(name: .init("zivlet-test-\(UUID())")); defer { board.releaseGlobally() }
        let action = ClipboardAction(pasteboard: board)
        _ = action.copyPaths([URL(fileURLWithPath: "/a b")], shellQuoted: true)
        #expect(board.string(forType: .string) == "'/a b'")
        #expect(action.copyPaths([URL(fileURLWithPath: "/x")], shellQuoted: false).toast == "Copied 1 path")
    }
}
```

### C2.2–C2.5

RED: `cannot find 'PathFormatter'`. GREEN: `swift test --filter ZivletActionsTests`. Commit `feat(actions): Copy and
Copy Path with shell-quoted Option variant`.

---

## Task C3 — AirDrop (P1-44)

| Field | Value |
|---|---|
| Goal | `AirDropAction` behind `protocol SharingService { func canPerform(_ items: [URL]) -> Bool; func perform(_ items: [URL], completion: @escaping (SharingOutcome) -> Void) }`; the real one wraps `NSSharingService(named: .sendViaAirDrop)` and retains itself until its delegate fires. `canPerform` false → error card "Zivlet couldn't start AirDrop for these files."; delegate `didFailToShareItems` with `NSUserCancelledError` (3072) → no card (silent); other errors → the same sentence plus "Show details" with the error's code; success → toast "Sent with AirDrop" (*new*) |
| 05 rows | P1-44 **[QA]** (real AirDrop is owner step O-6) |

**Files:** create `Sources/ZivletActions/AirDropAction.swift`, `Tests/ZivletActionsTests/AirDropActionTests.swift`.

### C3.1 Failing tests first

Fake `SharingService` cases: `canPerform` false → `.failed(.airDropUnavailable)` and `perform` never called;
user-cancel error → `.cancelled` (no card); generic error → `.failed(.airDropFailed(code:))`; success → `.done(toast:
"Sent with AirDrop")`; the real `SystemSharingService(named:)` returns `nil` for a bogus name and `canPerform([])` is
false (runs under `swift test`, no UI shown).

### C3.2–C3.5

RED: missing types. GREEN: `swift test --filter AirDropActionTests`. Commit `feat(actions): AirDrop with
availability check and silent user cancel`.

---

## Task C4 — Move planner and executor, with undo (P1-45, G-7)

| Field | Value |
|---|---|
| Goal | Pure `MovePlanner.plan(items:destination:volumes:existing:)` → `MovePlan` of steps `{source, target, kind: .rename | .copyThenTrash}` or a refusal: destination not a folder → `.notAFolder`; item is the destination or an ancestor of it (folder into itself) → `.intoItself(item)`; item already directly in the destination → skipped with `.alreadyThere`. Target names step through `name`, `name 2`, … using `OutputNamer` collision rules (cap 9,999). `MoveExecutor` runs steps: same volume → `renamex_np(src, dst, RENAME_EXCL)` stepping the name on `EEXIST` (race-safe, like `Publisher`); different volume → copy with `copyfile(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL)` into a hidden `.zivlet-move-<id>` name in the destination, verify byte size and item count, rename to the final name with `RENAME_EXCL`, then trash the source with `FileManager.trashItem`; a failed verify removes the copy and leaves the source. Every finished batch records an `UndoEntry.move(pairs:)`; undo moves each item back when the moved item still has the recorded inode, size and mtime and the original location is free, else lists it as skipped. Toast: "Moved 2 items · Undo"; partial: per-item failures in the card |
| 05 rows | P1-45, P1-15 (move entries), G-7 |
| Sources | 03b §7 row 4, 03a §4.7 |

**Files:** create `Sources/ZivletActions/MovePlanner.swift`, `Sources/ZivletActions/MoveExecutor.swift`,
`Tests/ZivletActionsTests/MovePlannerTests.swift`, `Tests/ZivletActionsTests/MoveExecutorTests.swift`; modify
`Sources/ZivletRuntime/UndoLog.swift` (`UndoEntry.Kind.move`), `UndoHistory.swift`, `Tests/ZivletRuntimeTests/UndoLogTests.swift`.

### C4.1 Failing tests first (planner excerpt; executor tests use real temp folders and a FAT32 disk image for the
cross-volume case, the same technique as M3 review #4)

```swift
@Suite("Move planner (P1-45)")
struct MovePlannerTests {
    let vol = VolumeID(1)

    @Test func collisionsGetTheNextFreeName() throws {
        let plan = try MovePlanner.plan(items: [Fx.file("/src/a.txt")], destination: Fx.folder("/dst"),
            volumes: { _ in vol }, existing: ["/dst/a.txt", "/dst/a 2.txt"])
        #expect(plan.steps.map(\.target.path) == ["/dst/a 3.txt"])
        #expect(plan.steps.map(\.kind) == [.rename])
    }

    @Test func aFolderCannotMoveIntoItselfOrItsChild() {
        #expect(throws: MoveRefusal.intoItself("/src/f")) {
            try MovePlanner.plan(items: [Fx.folder("/src/f")], destination: Fx.folder("/src/f/inner"),
                volumes: { _ in vol }, existing: [])
        }
    }

    @Test func itemsAlreadyThereAreSkipped() throws {
        let plan = try MovePlanner.plan(items: [Fx.file("/dst/a.txt")], destination: Fx.folder("/dst"),
            volumes: { _ in vol }, existing: ["/dst/a.txt"])
        #expect(plan.steps.isEmpty && plan.skipped == [.alreadyThere("/dst/a.txt")])
    }

    @Test func crossVolumeBecomesCopyThenTrash() throws {
        let plan = try MovePlanner.plan(items: [Fx.file("/src/a.txt")], destination: Fx.folder("/Volumes/USB"),
            volumes: { $0.path.hasPrefix("/Volumes/USB") ? VolumeID(2) : VolumeID(1) }, existing: [])
        #expect(plan.steps.map(\.kind) == [.copyThenTrash])
    }

    @Test func twoItemsWithTheSameNameGetDistinctTargets() throws {
        let plan = try MovePlanner.plan(items: [Fx.file("/x/a.txt"), Fx.file("/y/a.txt")], destination: Fx.folder("/d"),
            volumes: { _ in vol }, existing: [])
        #expect(plan.steps.map(\.target.lastPathComponent) == ["a.txt", "a 2.txt"])
    }
}
```

Executor tests (real files): same-volume move and undo restore the exact inode; a file created at the target between
plan and execute gets the next name (`EEXIST` race); cross-volume move onto a FAT32 image verifies and trashes the
source; a verify failure (injected short copy) leaves the source untouched and no `.zivlet-move-*` file; undo skips an
item that changed after the move and names it.

### C4.2–C4.5

RED: missing types. GREEN: `swift test --filter "ZivletActionsTests|ZivletRuntimeTests"`. Commits `feat(actions):
move planner with collision names and into-itself refusal`, `feat(actions): move executor with cross-volume copy,
verify and trash`, `feat(runtime): undo for moves`.

---

## Task C5 — Move Here panel and Terminal (P1-45)

| Field | Value |
|---|---|
| Goal | **Move:** after the wheel hides, one run-loop turn later (03b §7 "Ordering"), an `NSOpenPanel` (directories only, `canCreateDirectories`, prompt "Move Here", level above the wheel panel, starting in the first item's parent) runs as a sheet-less panel; Cancel is silent. **Terminal:** `TerminalCatalog` lists Terminal (`com.apple.Terminal`, default), iTerm2 (`com.googlecode.iterm2`), Ghostty (`com.mitchellh.ghostty`), WezTerm (`com.github.wez.wezterm`), Warp (`dev.warp.Warp-Stable`); installed = `NSWorkspace.urlForApplication(withBundleIdentifier:)` non-nil; `TerminalTargets.directories(for:)` keeps folders, maps files and packages to their parent, de-duplicates; opens with `NSWorkspace.open(dirs, withApplicationAt:configuration:)`. Stored id not installed → "<Name> isn't installed. Choose another in Settings."; unknown stored id → Terminal |
| 05 rows | P1-45 **[QA]** (each terminal verified by hand: owner step O-6, P-TERM) |

**Files:** create `Sources/ZivletActions/TerminalCatalog.swift`, `Sources/ZivletActions/TerminalAction.swift`,
`Sources/ZivletActions/MovePanel.swift` (AppKit, thin), tests `TerminalCatalogTests.swift` (pure: directories for
files/folders/packages, de-dup, unknown id → Terminal, missing app message) and `TerminalActionTests.swift` (fake
`WorkspaceOpening` records the URLs and app; Terminal.app is installed on every Mac so
`TerminalCatalog.installed()` contains it — a real-system assertion).

Commits `feat(actions): open folders in the chosen terminal` and `feat(actions): Move Here folder panel`.

---

## Task C6 — `ActionService`: one entry point, toasts and cards (P1-44, P1-45)

| Field | Value |
|---|---|
| Goal | `ActionService.perform(_ request: ActionRequest) async -> ActionOutcome` dispatches to C2–C5, returns `.done(toast:undoable:)`, `.partial(toast:failures:)`, `.failed(card)`, or `.cancelled`; results feed the HUD (D6 shows toasts in the same panel as conversion results, 1.5 s for toasts without Undo, 4 s held while hovered with Undo). Move records undo through `UndoHistory`. Rejected items from C1 always produce a card listing them, even when the rest succeeded |
| 05 rows | P1-44, P1-45 |

**Files:** create `Sources/ZivletActions/ActionService.swift`, `Tests/ZivletActionsTests/ActionServiceTests.swift`
(fakes for every port; table test over the five actions × {all ok, some rejected, failure, cancel}).

Commit `feat(actions): action service with toasts, failure cards and undo`.

---

## Task C7 — Wire actions into the app; hide FLOAT until P2-55 (D-M4-13)

| Field | Value |
|---|---|
| Goal | `AppDelegate.handle` routes `.action(id)` to `ActionService` (today it only logs, DEBUG HUD). The actions wheel shows five petals: `CapabilitySnapshot` gains `unavailableActions: Set<ActionID>` and the app passes `[.pinFloating]` until the Float shelf exists (P2-55). DEBUG demo argument `-ZivletDemoAction <path> <action> [-ZivletDemoOption YES]` runs an action without a drag (copy, copyFilePath and openInTerminal only; AirDrop and Move need a person) |
| 05 rows | P1-44, P1-45, M4 exit "5 actions" |

**Files:** modify `App/AppDelegate.swift`, `Sources/ZivletWheelCore/WheelContent.swift`,
`Sources/ZivletWheelCore/SliceBuilder.swift`, `Tests/ZivletWheelCoreTests/SliceBuilderTests.swift` (actions list has 5
entries when FLOAT is unavailable, 6 otherwise, order unchanged), `Sources/ZivletRuntime/DemoConversion.swift` →
split `DemoAction.swift`, `Scripts/demo-action.sh`, `Makefile` (`action-demo FILE=… ACTION=…`).

### C7.1 Failing test first

```swift
@Test func floatIsHiddenWhileUnavailableAndOrderIsKept() {
    let builder = SliceBuilder(catalog: .standard, capabilities: CapabilitySnapshot(unavailableTargets: [],
        unavailableActions: [.pinFloating]))
    let labels = builder.content(mode: .actions, items: [Fx.localFile("a.txt")]).sliceLabels
    #expect(labels == ["AIRDROP", "COPY", "MOVE", "COPY PATH", "TERMINAL"])
}
```

### C7.2–C7.5

RED: `extra argument 'unavailableActions'`. GREEN: `make test`; `make action-demo FILE=/abs/a.txt ACTION=copyFilePath`
→ `OK: pasteboard holds /abs/a.txt`. Commit `feat(app): run the five actions from the wheel; Float hidden until the
shelf exists`.

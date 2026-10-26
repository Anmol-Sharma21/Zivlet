# 16b — M5b Stream B: the Drop Box panel (NB3)

Part of [16-implementation-plan-m5b](16-implementation-plan-m5b.md). Conventions: index §6. Look:
[design/19c-drop-box-look](../design/19c-drop-box-look.md). Behaviour: [design/17e-app](../design/17e-app.md) §2.3.
Acceptance: 05 rows P2-55 (§9.1 and §9.5). Swift below is specification-grade and was not compiled.

---

## Task B1 — `ZivletBox` module; `FileDragSource` moves to `ZivletActions` (D-M5b-1)

| Field | Value |
|---|---|
| Goal | Add target `ZivletBox` (deps `ZivletCore`, `ZivletShelfCore`, `ZivletActions`, `ZivletNotchCore`, `ZivletNotch`; `shell`), test target `ZivletBoxTests` (deps `ZivletBox`, `ZivletShelfCore`, `TestSupport`, `NotchTestSupport`; `shell`), both in the `ZivletKit` product; `ZivletBox` in `GATED_MODULES`. Move `FileDragSource` and `DragSourceView` from `ZivletUI/HUD/FileDragSource.swift` to `ZivletActions/FileDragSource.swift`, `public`, unchanged in behaviour, so the box and the HUD share one multi-item drag source |
| Acceptance | `ResultCardTests`, `NotchCardLayoutTests`, `HUDTests` green before and after the move; `make test lint coverage app` pass; coverage lists 16 modules |
| Effort | S |

**Files:** create `Sources/ZivletBox/Box.swift` (module doc comment), `Tests/ZivletBoxTests/BoxModuleTests.swift`,
`Sources/ZivletActions/FileDragSource.swift`; delete `Sources/ZivletUI/HUD/FileDragSource.swift`; modify
`Package.swift`, `Scripts/coverage.sh`, `Sources/ZivletUI/HUD/ResultCardContent.swift` and
`Sources/ZivletUI/Notch/NotchResultCard.swift` (imports only).

RED for the module: `no such module 'ZivletBox'`. The move is a refactor: `swift test --filter
"ResultCard|NotchCard|HUDTests"` before and after, both green. Commits `chore(box): add the ZivletBox module, its
tests and the coverage gate` and `refactor(actions): share the multi-item drag source with the Drop Box`.

---

## Task B2 — `BoxPresentation`, `DockSnapper`, frame clamping (19c §4.1, 17e §2.3)

| Field | Value |
|---|---|
| Goal | Pure values in `ZivletShelfCore`. `BoxPresentation { base: .hidden \| .docked(DockEdge) \| .collapsed \| .expanded; overlay: nil \| .dropTarget(count:) \| .busy(verb:, fraction:) \| .confirm(ConfirmKind); missing: Int; isEmpty: Bool }` with `handling(_ event:) -> (BoxPresentation, [BoxPresentationEffect])`. Events: `show`, `hide`, `dock(edge)`, `undock`, `click`, `escape`, `dragEntered(count:)`, `dragExited`, `dropped`, `busyStarted(verb:)`, `progress(_:)`, `busyEnded`, `confirmRequested(_:)`, `confirmAnswered(_:)`, `itemsChanged(count:missing:)`. Escape: confirm → cancelled; expanded → collapsed (or docked when it has a dock edge); collapsed → hidden. A drop target returns to the base it interrupted, or to expanded after a drop. `DockSnapper` (attach within 28 pt of a left or right visible-frame edge, detach after 48 pt, a move under 8 pt is a click) and `PanelFrames.clamped(_:to:)` (a saved frame on a display that is gone moves to the first display, inside its visible frame) |
| Acceptance | a table test with one row per (base or overlay) × event, as `IslandMachineTable` does for the island, so a new event without a row fails; dock tests at 27/28/29 pt and 47/48/49 pt; clamping tests with the recorded and constructed display fixtures (as `Rect2D` values) |
| Effort | M |

**Files:** create `Sources/ZivletShelfCore/BoxPresentation.swift`, `Sources/ZivletShelfCore/BoxPresentationEvent.swift`,
`Sources/ZivletShelfCore/DockSnapper.swift`, `Sources/ZivletShelfCore/PanelFrames.swift`,
`Tests/ZivletShelfCoreTests/BoxPresentationTable.swift`, `Tests/ZivletShelfCoreTests/BoxPresentationTests.swift`,
`Tests/ZivletShelfCoreTests/DockSnapperTests.swift`.

```swift
@Suite("Box presentation (P2-55 states)")
struct BoxPresentationTests {
    @Test func escapeStepsDownOneState() {
        let open = BoxPresentation(base: .expanded)
        #expect(open.handling(.escape).0.base == .collapsed)
        #expect(BoxPresentation(base: .expanded, dock: .right).handling(.escape).0.base == .docked(.right))
    }

    @Test func aDropTargetReturnsToWhatItInterrupted() {
        let docked = BoxPresentation(base: .docked(.left))
        let hovering = docked.handling(.dragEntered(count: 3)).0
        #expect(hovering.overlay == .dropTarget(count: 3))
        #expect(hovering.handling(.dragExited).0 == docked)
        #expect(hovering.handling(.dropped).0.base == .expanded)
    }

    @Test func missingItemsRaiseAttentionWithoutChangingTheBase() {
        let next = BoxPresentation(base: .expanded).handling(.itemsChanged(count: 12, missing: 2)).0
        #expect(next.base == .expanded && next.missing == 2)
    }

    @Test func everyEventHasARowForEveryState() { BoxPresentationTable.assertComplete() }
}

@Suite("Dock (attach 28, detach 48, click under 8)")
struct DockSnapperTests {
    @Test(arguments: [(27.0, true), (28.0, true), (29.0, false)])
    func attachesNearAnEdge(_ gap: Double, _ docks: Bool) { /* frame gap pt from the right edge */ }
}
```

RED: `cannot find 'BoxPresentation' in scope`. Commit `feat(shelf): add the Drop Box presentation states and the
dock rules`.

---

## Task B3 — Tokens, finish, contrast and symbols (19c §2–§3, D-M5b-22)

| Field | Value |
|---|---|
| Goal | Move the 19b content tokens from `ZivletUI/Notch/NotchLook.swift` and `NotchInk.swift` into `ZivletNotch` as public `IslandContentLook` and `IslandInk`, so the box and the HUD share one set; `ZivletUI` keeps its names through `typealias NotchLook = IslandContentLook` and `typealias NotchInk = IslandInk`, and their tests move to `ZivletNotchTests`. Add `BoxLook` in `ZivletBox` with only the box's own tokens (19c §3.1–§3.4: panel, grid, list, tab, tray). `BoxFinish.resolve(_ settings: IslandFinish.Settings) -> .glass \| .solid \| .contrast` reuses the island's pure finish rule. `BoxSymbols.all` lists every symbol of 19c §3.5 |
| Acceptance | `NotchLookTests`, `NotchInkTests` green after the move; new tests compute each row of 19c §3.6 from the tokens (≥ 4.5:1 for text, ≥ 3:1 for the badge); every name in `BoxSymbols.all` resolves with `NSImage(systemSymbolName:accessibilityDescription:)`; `panel.width == 2 × l + 5 × cell.width + 4 × cell.gap` |
| Effort | S |

**Files:** create `Sources/ZivletNotch/IslandContentLook.swift`, `Sources/ZivletNotch/IslandInk.swift`,
`Sources/ZivletBox/BoxLook.swift`, `Sources/ZivletBox/BoxFinish.swift`, `Sources/ZivletBox/BoxSymbols.swift`,
`Tests/ZivletBoxTests/BoxLookTests.swift`; delete `Sources/ZivletUI/Notch/NotchLook.swift` and `NotchInk.swift`
(replaced by `Sources/ZivletUI/Notch/NotchTokens.swift` with the two typealiases); move
`Tests/ZivletUITests/NotchLookTests.swift` and `NotchInkTests.swift` to `Tests/ZivletNotchTests/`.

```swift
@Suite("Drop Box tokens (19c §3)")
@MainActor
struct BoxLookTests {
    @Test func cellNamesAreWhiteBecauseSmallTextNeedsTheMargin() {
        #expect(IslandInk.contrast(of: BoxLook.Grid.nameInk, on: IslandLook.worstGlassLuminance) >= 6.0)
    }

    @Test func secondaryTextPassesOnTheWorstGlass() {
        #expect(IslandInk.contrast(of: IslandContentLook.Ink.secondary, on: IslandLook.worstGlassLuminance) >= 4.5)
    }

    @Test func theDefaultWidthHoldsFiveCells() {
        #expect(BoxLook.Panel.width == 2 * IslandContentLook.Spacing.l + 5 * BoxLook.Grid.cell + 4 * BoxLook.Grid.gap)
    }

    @Test(arguments: BoxSymbols.all)
    func everySymbolExists(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }
}
```

RED: `cannot find 'BoxLook' in scope`. Commits `refactor(notch): share the island's content tokens with the Drop
Box` and `feat(box): add the Drop Box tokens, finish and symbols`.

---

## Task B4 — `BoxPanel`

| Field | Value |
|---|---|
| Goal | `BoxPanel: NSPanel`: borderless and non-activating, level `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`, transparent, system shadow, `hidesOnDeactivate = false`, `becomesKeyOnlyIfNeeded = true`, `canBecomeKey` true, `canBecomeMain` false, `appearance = darkAqua` (19c D-BL1), movable by background (the dock rules decide where it lands). `cancelOperation` and key changes go to closures, as `IslandPanel` does. Shown with `orderFrontRegardless()`, never `makeKeyAndOrderFront` (prototype §3.1: showing kept the frontmost app) |
| Acceptance | shell test of every property; showing does not make it key; a click into a non-button area makes it key (simulated with `makeKey()`), and Escape reaches the closure |
| Effort | S |

**Files:** create `Sources/ZivletBox/BoxPanel.swift`, `Tests/ZivletBoxTests/BoxPanelTests.swift`.

```swift
@Suite("Drop Box panel (P2-55: non-activating, every Space)")
@MainActor
struct BoxPanelTests {
    @Test func itFloatsOnEverySpaceWithoutActivating() {
        let panel = BoxPanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.level == .floating)
        #expect(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
        #expect(panel.canBecomeKey && !panel.canBecomeMain && panel.becomesKeyOnlyIfNeeded)
        #expect(panel.appearance?.name == .darkAqua)
    }

    @Test func showingDoesNotTakeTheKeyboard() {
        let panel = BoxPanel()
        panel.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        panel.show()
        #expect(panel.isVisible && !panel.isKeyWindow)
    }
}
```

RED: `cannot find 'BoxPanel' in scope`. Commit `feat(box): add the non-activating Drop Box panel`.

---

## Task B5 — `ThumbnailCache` and type icons (D-M5b-14, 19c D-BL11)

| Field | Value |
|---|---|
| Goal | `ThumbnailCache` (main actor) with a `ThumbnailMaking` port (system: `QLThumbnailGenerator`, 48 pt and 40 pt at the screen's scale): `placeholder(for item:) -> NSImage` is the system icon for the item's **type** (`NSWorkspace.shared.icon(for: UTType)` from the name's extension; no file access); `thumbnail(for:visible:) async -> NSImage?` runs at most 4 requests at a time, only for items marked visible, caches by item ID and size class in an `NSCache` (count limit 400), and cancels requests for items that scroll out. Callbacks never touch the main thread except to publish the image |
| Acceptance | with a fake maker: a fifth request waits until one of four finishes; an item that leaves the visible set is cancelled; a second request for the same item hits the cache; the placeholder path calls no file-system port (a fake that fails the test when called) |
| Effort | S |

**Files:** create `Sources/ZivletBox/ThumbnailCache.swift`, `Sources/ZivletBox/ThumbnailMaking.swift`,
`Tests/ZivletBoxTests/ThumbnailCacheTests.swift`.

RED: `cannot find 'ThumbnailCache' in scope`. Commit `feat(box): make Quick Look thumbnails off the main thread with
type icons first`.

---

## Task B6 — Views (19c §4.1)

| Field | Value |
|---|---|
| Goal | SwiftUI views in `ZivletBox`, driven by one immutable `BoxViewModel` (items with status and thumbnail, totals, selection, presentation, finish) and press closures; no action logic in views. `BoxCard` (finish, scrim, radius, outline under Increase Contrast), `BoxHeader`, `BoxGrid` with `BoxCell`, `BoxList` with `BoxRow`, `BoxActionBar` (five icon buttons + overflow menu, 19b D-NL9 buttons from `IslandContentLook`), `BoxDockTab`, `BoxCollapsedCard`, `BoxCompactView` (also the tray's expanded content, D11), `BoxEmpty`, `BoxConfirmLine`, `BoxDropOverlay`, attention badges. Every button carries its 19c §5 word as tooltip and accessibility label. The panel is one accessibility list; each row's label is 19c §5's spoken form, built by a pure `BoxSpeech` function |
| Acceptance | layout tests rendered on the **solid** finish with `ImageRenderer` (sizes, not pixels of glass: 19b §7): the panel's width is `BoxLook.Panel.width`; the grid wraps at 5; the list row is 36 pt; the collapsed card is 88 pt high; names truncate in the middle. `BoxSpeech` tests for present, missing, in the Trash and offline items. An accessibility test finds one list with N rows and labelled buttons |
| Effort | M |

**Files:** create `Sources/ZivletBox/Views/BoxViewModel.swift`, `BoxCard.swift`, `BoxHeader.swift`, `BoxGrid.swift`,
`BoxCell.swift`, `BoxList.swift`, `BoxRow.swift`, `BoxActionBar.swift`, `BoxDockTab.swift`, `BoxCollapsedCard.swift`,
`BoxCompactView.swift`, `BoxEmpty.swift`, `BoxConfirmLine.swift`, `BoxDropOverlay.swift`, `BoxBadge.swift`,
`Sources/ZivletBox/BoxSpeech.swift`; tests `Tests/ZivletBoxTests/BoxLayoutTests.swift`, `BoxSpeechTests.swift`,
`BoxAccessibilityTests.swift`, `BoxViewFixtures.swift`.

```swift
@Suite("Box speech (19c §5)")
struct BoxSpeechTests {
    @Test func aPresentItemSaysNameSizeAndFolder() {
        #expect(BoxSpeech.item("photo.heic", bytes: 2_100_000, status: .present(path: "/Users/u/Downloads/photo.heic"))
            == "photo.heic, 2.1 MB, in Downloads")
    }

    @Test func anOfflineItemNamesItsVolume() {
        #expect(BoxSpeech.item("a.mov", bytes: nil, status: .volumeOffline(name: "Backup"))
            == "a.mov, on Backup, not connected")
    }
}
```

RED: `cannot find 'BoxSpeech' in scope`. Commit `feat(box): draw the Drop Box states with glass, icon buttons and an
accessible list`.

---

## Task B7 — Intake: drop view, URL validation, promises, clippings (D-M5b-4, D-M5b-5)

| Field | Value |
|---|---|
| Goal | `BoxDropView: NSView` registered for file URLs, the file-promise types and text/image clippings; it forwards `NSDraggingInfo` to `BoxIntake`. `BoxIntake.preview(_ info:) -> Int` reads **only** the pasteboard item count (for "Add 3"); `BoxIntake.receive(_ info:, box:) async -> IntakeResult` runs inside `performDragOperation`: file URLs (validated: `isFileURL`, absolute, not inside `OwnedStorage.root`, deduplicated) become new items through `BookmarkMaking`; promises go through `PromiseReceiving` (system: `NSFilePromiseReceiver.receivePromisedFiles(atDestination:options:operationQueue:reader:)` into `OwnedStorage.reserve`); text and image clippings are written as owned files ("Clipping.txt", "Clipping.png", *new*). `IntakeResult { items, rejected: [String] (names with reasons), ownedBytes }` |
| Acceptance | with a fake `NSDraggingInfo` (the prototype's seam) on a private pasteboard: 200 file URLs become 200 items; a URL inside the box storage is refused; promises go to the fake receiver (AppKit raises when receiving outside a real session, so the system receiver is exercised only by QA rows B6–B8); `preview` makes no file-system call (a fake `BookmarkMaking` that fails when called) |
| Effort | M |

**Files:** create `Sources/ZivletBox/BoxDropView.swift`, `Sources/ZivletBox/BoxIntake.swift`,
`Sources/ZivletBox/PromiseReceiving.swift`, `Sources/ZivletBox/IntakeResult.swift`,
`Tests/ZivletBoxTests/BoxIntakeTests.swift`, `Tests/ZivletBoxTests/FakeDraggingInfo.swift` (moved to
`NotchTestSupport` in D9 when the island needs it too).

```swift
@Suite("Box intake (P2-141 owned copies, D-M5b-4, D-M5b-5)")
@MainActor
struct BoxIntakeTests {
    @Test func twoHundredFilesBecomeTwoHundredItems() async throws {
        let dir = try TempDir()
        let urls = try (0..<200).map { try dir.file("f\($0).txt") }
        let info = FakeDraggingInfo(fileURLs: urls)
        let result = await BoxIntake(rig: .standard(dir)).receive(info, box: UUID())
        #expect(result.items.count == 200 && result.rejected.isEmpty)
    }

    @Test func thePreviewReadsOnlyThePasteboard() {
        let intake = BoxIntake(rig: .failingFileSystem)
        #expect(intake.preview(FakeDraggingInfo(fileURLs: [URL(filePath: "/Users/u/Downloads/a.txt")])) == 1)
    }

    @Test func promisesGoThroughThePort() async throws { /* fake receiver writes two files into owned storage */ }
}
```

RED: `cannot find 'BoxIntake' in scope`. Commit `feat(box): take files, promises and clippings into the box`.

---

## Task B8 — `BoxController`: add, restore, selection, keys, Quick Look, drag-out

| Field | Value |
|---|---|
| Goal | `BoxController` (main actor) owns the `ShelfLibrary`, `BoxStore`, resolver, `OwnedStorage`, `BoxPresentation`, the panel and the thumbnail cache. `start()` loads the store (no resolution); `showPanel(anchor:)` resolves the current box lazily, refreshes stale bookmarks and saves; `add(_ urls:, newBox:) async -> AddOutcome` (the BOX slice, the panel and the tray all call it); `Shelf` gains an optional `shown` base so the panel's last state and frame are restored after relaunch (schema stays 1; a missing field decodes as hidden). Selection: click, ⇧-click, ⌘-click, ⌘A, arrows, marquee (`GridSelection.marquee(_:cells:)`, pure), type-to-select with a 0.8 s reset (`TypeSelect`, pure, injected clock). `BoxKeyMap` (pure) maps 17e §2.3's keys to `BoxCommand`s. Context menu built from the same command list. Quick Look through a `QuickLookPresenting` port (system: `QLPreviewPanel`; the panel becomes key on Space as a click would). Drag-out with the shared `FileDragSource` of the selection or all items; a drag from the panel holds it open |
| Acceptance | with fakes: `start()` resolves nothing; `showPanel` resolves once and saves refreshed bookmarks; a relaunch (new controller, same store) restores the base, frame and dock; `add` of a duplicate reports it; the key map covers every row of 17e §2.3; type-to-select resets after 0.8 s; Space calls the Quick Look port with the selection; a drag-out offers every selected item |
| Effort | M |

**Files:** create `Sources/ZivletBox/BoxController.swift`, `Sources/ZivletBox/BoxController+Selection.swift`,
`Sources/ZivletBox/BoxKeyMap.swift`, `Sources/ZivletBox/GridSelection.swift`, `Sources/ZivletBox/TypeSelect.swift`,
`Sources/ZivletBox/QuickLookPresenting.swift`; modify `Sources/ZivletShelfCore/Shelf.swift` (`shown`); tests
`Tests/ZivletBoxTests/BoxControllerTests.swift`, `BoxRestoreTests.swift`, `BoxKeyMapTests.swift`,
`GridSelectionTests.swift`, `TypeSelectTests.swift`, `BoxFakes.swift`.

```swift
@Suite("Restore after relaunch (P2-55 §9.5)")
@MainActor
struct BoxRestoreTests {
    @Test func theBoxComesBackWhereItWas() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.start()
        _ = await first.add(try rig.files(3), newBox: false)
        first.dock(.right)
        first.quit()
        let second = rig.controller()
        second.start()
        #expect(second.presentation.base == .docked(.right) && second.library.current?.items.count == 3)
        #expect(rig.resolver.calls == 0)  // lazy: nothing resolved until shown
    }
}
```

RED: `cannot find 'BoxController' in scope`. Commit `feat(box): add the Drop Box controller with restore,
selection, keys and Quick Look`.

---

## Task B9 — BOX slice, menu command, Settings rows, app wiring (OWN-APP-1)

| Field | Value |
|---|---|
| Goal | `ActionID.pinFloating` keeps its raw value; `wheelLabel` "BOX", `symbolName` `tray.full`. `ActionError.floatNotYetAvailable` and its copy are removed; `ActionService` takes a `BoxAdding` port (`add(_ urls:, newBox:) async -> ActionOutcome`, declared in `ZivletActions`) and `.pinFloating` calls it with `newBox: optionHeld` ("Added 3" toast, *new*). `ActionWiring.unavailableActions` becomes empty. `MenuAction.showDropBox`, menu title "Show Drop Box" after "Show Progress and Results". Settings › General gains a "Drop Box" section: "Open at the notch while dragging" (toggle), "Shake to open" (toggle), "Clear items: Never \| After they leave the box \| After 24 hours", "New drops go to: The last box \| A new box" (all *new*, 19c §5). `App/BoxWiring.swift` builds one `BoxController` with the standard stores, gives `ActionWiring` the `BoxAdding` adapter, handles the menu command, restores on launch, saves on quit, and maps the settings group |
| Acceptance | `ToolCatalogTests` expects "BOX"; `SliceBuilderTests` no longer hides the slice; `ActionServiceTests`: `.pinFloating` reaches the fake port with `newBox` from ⌥; `MenuModelTests`: the entry and its place; a Settings pane snapshot test for the new rows; `make app` builds; the Debug app shows the BOX slice (owner row B1) |
| Effort | M |

**Files:** modify `Sources/ZivletCore/Catalog/ActionID.swift`, `Sources/ZivletActions/ActionService.swift`,
`Sources/ZivletActions/ActionError.swift`, `Sources/ZivletUI/Menu/MenuModel.swift`, `Sources/ZivletUI/Settings/GeneralPane.swift`,
`App/ActionWiring.swift`, `App/AppDelegate.swift`, `App/StatusMenu.swift`, `App/SettingsWiring.swift`; create
`Sources/ZivletActions/BoxAdding.swift`, `App/BoxWiring.swift`; tests `Tests/ZivletCoreTests/ToolCatalogTests.swift`,
`Tests/ZivletWheelCoreTests/SliceBuilderTests.swift`, `Tests/ZivletActionsTests/ActionServiceTests.swift`,
`Tests/ZivletUITests/MenuModelTests.swift`, `Tests/ZivletUITests/SettingsPaneSnapshotTests.swift`.

```swift
@Test func theBoxSliceAddsToTheCurrentBoxOrANewOneWithOption() async throws {
    let box = FakeBoxAdding()
    let rig = ActionRig(box: box)
    _ = await rig.perform(.pinFloating, [try rig.file("a.txt")], optionHeld: true)
    #expect(box.calls == [.init(count: 1, newBox: true)])
}
```

RED: `ToolCatalogTests` fails on "FLOAT" ≠ "BOX"; `cannot find 'BoxAdding' in scope`. Commits `feat(actions): the
BOX slice adds to the Drop Box`, `feat(ui): Show Drop Box and the Drop Box settings`, `feat(app): wire the Drop Box
into the app`.

---

## Task B10 — Debug previews and their refusal in Release (D-M5b-20)

| Field | Value |
|---|---|
| Goal | Debug-only launch flags, parsed and validated like `IslandShotFlags`: `-ZivletBoxPreview hidden\|docked\|collapsed\|grid\|list\|selection\|dropTarget\|busy\|attention\|confirmTrash\|confirmClear\|empty` (made-up items with type icons, no files read) and `-ZivletBoxDemo <folder>` (adds the folder's files to a fresh demo box in a temporary store, never the person's `boxes.json`); the finish flags of plan 14 (`-ZivletIslandFinish`, `-ZivletIslandBackdrop`) apply to the panel too. The app logs `Box: frame x y w h` (whole numbers) and `Box: <state>` for the demo scripts. `check-release-paths.sh` refuses `-ZivletBoxPreview` and `-ZivletBoxDemo` in a Release binary, like `-ZivletIslandPreview` |
| Acceptance | flag parsing tests (unknown state refused with a public log line naming the flag only); the scan test fails on a file containing either flag and passes on one without |
| Effort | S |

**Files:** create `App/BoxShots.swift` (`#if DEBUG`), `Sources/ZivletBox/BoxShotFlags.swift` (pure parsing),
`Tests/ZivletBoxTests/BoxShotFlagsTests.swift`, `Scripts/tests/test-release-flags.sh`; modify
`Scripts/check-release-paths.sh`, `App/BoxWiring.swift`.

RED: `cannot find 'BoxShotFlags' in scope`; the script test fails until the scan knows the flags. Commits
`feat(app): debug previews of every Drop Box state` and `test(scripts): refuse the Drop Box debug flags in Release`.

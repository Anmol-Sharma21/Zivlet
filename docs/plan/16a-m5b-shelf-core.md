# 16a — M5b Stream A: shelf core (NB1) and shake detector (NB2)

Part of [16-implementation-plan-m5b](16-implementation-plan-m5b.md). Conventions: index §6. Decisions: index §4.
Behaviour: [design/17e-app](../design/17e-app.md) §2.3–§2.4. Acceptance: 05 row P2-141. Swift below is
specification-grade and was not compiled for this plan; each RED line names the expected failure.

Commands for every task (index §6): `cd Packages/ZivletKit && nice -n 10 swift test --filter <Suite>` for RED and
GREEN, then `nice -n 10 make test lint`, and `nice -n 10 make coverage` when a gated module changed.

---

## Task A0 — Baseline

| Field | Value |
|---|---|
| Goal | Start from a green `m5b`: `nice -n 10 make test lint` exit 0. Note the test count per bundle (the plan's run: 15 bundles, 1240 tests) |
| Acceptance | both exit 0; otherwise stop and report before A1 (no M5b code on a red tree) |
| Effort | S |

No commit.

---

## Task A1 — `ZivletShelfCore` module, test target, coverage gate (D-M5b-1)

| Field | Value |
|---|---|
| Goal | Add target `ZivletShelfCore` (deps `ZivletCore`, `strict`), test target `ZivletShelfCoreTests` (deps `ZivletShelfCore`, `TestSupport`, `strict`), add the module to the `ZivletKit` product and to `GATED_MODULES` in `Scripts/coverage.sh`. The module imports Foundation (and `os` for logging) only |
| Acceptance | `make test lint coverage` pass; coverage lists 15 modules |
| Effort | S |

**Files:** create `Sources/ZivletShelfCore/ShelfCore.swift` (module doc comment: "The Drop Box's data: boxes, items,
bookmarks, the store and plans. Pure values; file access only behind small ports with Foundation implementations"),
`Tests/ZivletShelfCoreTests/ShelfModuleTests.swift`; modify `Package.swift`, `Scripts/coverage.sh`.

```swift
@Suite("ZivletShelfCore module (D-M5b-1)")
struct ShelfModuleTests {
    @Test func theModuleSeesTheCore() { #expect(Rect2D(x: 0, y: 0, width: 2, height: 2).maxX == 2) }
}
```

RED: `no such module 'ZivletShelfCore'`. Commit `chore(shelf): add the ZivletShelfCore module, its tests and the
coverage gate`.

---

## Task A2 — `ShelfItem`, ownership, identity, validation

| Field | Value |
|---|---|
| Goal | `FileIdentity { volumeUUID: String, fileID: UInt64 }` (`Hashable`, `Codable`). `ShelfItem { id: UUID, bookmark: Data, lastKnownPath: String, displayName: String, byteCount: Int64?, addedAt: Date, ownership: Ownership, identity: FileIdentity? }` with `Ownership = .reference \| .owned(relativePath: String)`. A throwing validating init (also used by `init(from:)`): bookmark 1…16,384 bytes; `lastKnownPath` absolute, ≤ 4,096 bytes; `displayName` 1…255 UTF-8 bytes without control characters or `/`; `byteCount` ≥ 0 when present; an owned path is relative, without `..` components. Edits return new values: `relocated(to:bookmark:)`, `withSize(_:)` |
| Acceptance | tests below green; `ShelfError` has one case per rule with a `userMessage` in Zivlet's words |
| Effort | S |

**Files:** create `Sources/ZivletShelfCore/ShelfItem.swift`, `Sources/ZivletShelfCore/FileIdentity.swift`,
`Sources/ZivletShelfCore/ShelfError.swift`, `Tests/ZivletShelfCoreTests/ShelfItemTests.swift`,
`Tests/ZivletShelfCoreTests/ShelfFixtures.swift` (an `item(_ name:)` helper with a one-byte bookmark).

```swift
@Suite("Shelf item (P2-141): immutable, validated at the boundary")
struct ShelfItemTests {
    @Test func aValidItemKeepsItsValues() throws {
        let item = try ShelfFixtures.item("photo.heic", size: 2_100_000)
        #expect(item.displayName == "photo.heic" && item.ownership == .reference && item.byteCount == 2_100_000)
    }

    @Test(arguments: [Data(), Data(count: 16_385)])
    func badBookmarksAreRefused(_ bookmark: Data) {
        #expect(throws: ShelfError.self) { try ShelfFixtures.item("a.txt", bookmark: bookmark) }
    }

    @Test(arguments: ["", "a/b", "line\nbreak", String(repeating: "é", count: 128)])
    func badNamesAreRefused(_ name: String) {
        #expect(throws: ShelfError.self) { try ShelfFixtures.item(name) }
    }

    @Test func aRelativeLastKnownPathIsRefused() {
        #expect(throws: ShelfError.relativePath("Downloads/a.txt")) {
            try ShelfFixtures.item("a.txt", path: "Downloads/a.txt")
        }
    }

    @Test func anOwnedPathMayNotLeaveItsFolder() {
        #expect(throws: ShelfError.self) { try ShelfFixtures.item("a.txt", ownership: .owned(relativePath: "../x")) }
    }

    @Test func relocatingReturnsANewItemAndLeavesTheOldOne() throws {
        let item = try ShelfFixtures.item("a.txt", path: "/Users/u/Downloads/a.txt")
        let moved = item.relocated(to: "/Users/u/Desktop/a.txt", bookmark: Data([2]))
        #expect(moved.lastKnownPath.hasSuffix("Desktop/a.txt") && item.lastKnownPath.hasSuffix("Downloads/a.txt"))
        #expect(moved.id == item.id)
    }

    @Test func decodingRunsTheSameRules() throws {
        let json = #"{"id":"6F1E2B9C-0000-4000-8000-000000000001","bookmark":"","lastKnownPath":"/a","displayName":"a","addedAt":0,"ownership":{"reference":{}}}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ShelfItem.self, from: Data(json.utf8)) }
    }
}
```

RED: `cannot find 'ShelfItem' in scope`. Commit `feat(shelf): add validated, immutable Drop Box items`.

---

## Task A3 — `Shelf` and `ShelfLibrary`: add with de-dup, remove, reorder, current box, caps, totals

| Field | Value |
|---|---|
| Goal | `Shelf { id, name, items, frame: Rect2D?, dock: DockEdge?, viewMode: .grid \| .list, updatedAt }` and `ShelfLibrary { boxes: [Shelf], currentID: UUID? }`, both `Codable`, `Equatable`, `Sendable`. Operations return new values: `Shelf.adding(_:cap:) -> (Shelf, AddReport)`, `removing(_ ids:)`, `reordering(_ ids:)`, `renamed(_:)`, `totals` (`count`, `bytes`, `ownedBytes`, `unknownSizes`); `ShelfLibrary.adding(_:to: .current \| .newBox, now:)`, `replacing(_:)`, `removingBox(_:)`, `makingCurrent(_:)`, `current`. De-dup: same `FileIdentity` when both items have one, else the same standardised `lastKnownPath`. Caps (D-M5b-18): 8 boxes, 2,000 items per box; items over the cap are reported, not added. The current box is the most recently used (OWN-APP-1); `.newBox` makes "Box 2", "Box 3" … (*new*), the first box is "Box" |
| Acceptance | tests below; every operation leaves its receiver unchanged (one test per operation compares the receiver before and after) |
| Effort | M |

**Files:** create `Sources/ZivletShelfCore/Shelf.swift`, `Sources/ZivletShelfCore/ShelfLibrary.swift`,
`Sources/ZivletShelfCore/AddReport.swift`, `Sources/ZivletShelfCore/DockEdge.swift`,
`Tests/ZivletShelfCoreTests/ShelfTests.swift`, `Tests/ZivletShelfCoreTests/ShelfLibraryTests.swift`.

```swift
@Suite("Shelf (P2-141): add, de-dup, caps, totals")
struct ShelfTests {
    @Test func theSameFileTwiceIsAddedOnce() throws {
        let a = try ShelfFixtures.item("a.txt", identity: FileIdentity(volumeUUID: "V", fileID: 7))
        let again = try ShelfFixtures.item("a renamed.txt", identity: FileIdentity(volumeUUID: "V", fileID: 7))
        let (shelf, report) = Shelf.empty(name: "Box").adding([a, again], cap: 2_000)
        #expect(shelf.items.count == 1 && report.duplicates == ["a renamed.txt"])
    }

    @Test func withoutIdentitiesThePathDecides() throws {
        let a = try ShelfFixtures.item("a.txt", path: "/x/a.txt")
        let b = try ShelfFixtures.item("a.txt", path: "/x/./a.txt")
        #expect(Shelf.empty(name: "Box").adding([a, b], cap: 10).0.items.count == 1)
    }

    @Test func itemsOverTheCapAreReportedNotAdded() throws {
        let items = try (0..<5).map { try ShelfFixtures.item("f\($0).txt", path: "/x/f\($0).txt") }
        let (shelf, report) = Shelf.empty(name: "Box").adding(items, cap: 3)
        #expect(shelf.items.count == 3 && report.overCap.count == 2)
    }

    @Test func totalsCountUnknownSizesSeparately() throws {
        let shelf = Shelf.empty(name: "Box").adding(
            [try ShelfFixtures.item("a", size: 10), try ShelfFixtures.item("b", size: nil, path: "/b")], cap: 10).0
        #expect(shelf.totals.bytes == 10 && shelf.totals.unknownSizes == 1)
    }

    @Test func addingLeavesTheReceiverUnchanged() throws {
        let shelf = Shelf.empty(name: "Box")
        _ = shelf.adding([try ShelfFixtures.item("a")], cap: 10)
        #expect(shelf.items.isEmpty)
    }
}

@Suite("Shelf library (OWN-APP-1, D-M5b-18)")
struct ShelfLibraryTests {
    @Test func dropsGoToTheMostRecentBox() throws {
        let lib = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .current, now: .t0).0
        let next = try lib.adding([ShelfFixtures.item("b", path: "/b")], to: .current, now: .t1).0
        #expect(next.boxes.count == 1 && next.current?.items.count == 2)
    }

    @Test func optionMakesANewNumberedBox() throws {
        let lib = try ShelfLibrary().adding([ShelfFixtures.item("a")], to: .current, now: .t0).0
        let two = try lib.adding([ShelfFixtures.item("b", path: "/b")], to: .newBox, now: .t1).0
        #expect(two.boxes.map(\.name) == ["Box", "Box 2"] && two.current?.name == "Box 2")
    }

    @Test func aNinthBoxIsRefused() throws {
        var lib = ShelfLibrary()
        for i in 0..<8 { lib = try lib.adding([ShelfFixtures.item("f\(i)", path: "/f\(i)")], to: .newBox, now: .t0).0 }
        #expect(throws: ShelfError.tooManyBoxes) {
            try lib.adding([ShelfFixtures.item("g", path: "/g")], to: .newBox, now: .t1)
        }
    }

    @Test func removingTheCurrentBoxMakesTheMostRecentOtherCurrent() throws { /* two boxes, remove current */ }
}
```

RED: `cannot find 'Shelf' in scope`. Commit `feat(shelf): add boxes and the box library with de-dup and caps`.

---

## Task A4 — Bookmark port, system bookmarks, item status, refresh (D-M5b-2, D-M5b-3)

| Field | Value |
|---|---|
| Goal | Ports: `BookmarkMaking` (`bookmark(for:) throws(ShelfError) -> Data`, `identity(of:) -> FileIdentity?`, `size(of:) -> Int64?`) and `BookmarkResolving` (`resolve(_:) -> Resolution`). `Resolution = .resolved(path:, stale:) \| .failed(code:, storedVolumePath:, storedVolumeName:)`. `ItemStatus = .present(path:) \| .inTrash(path:) \| .volumeOffline(name:) \| .missing`. The pure rule `ItemStatus.from(_ resolution:, isMounted:)`: a resolved path with a `.Trash` or `.Trashes` component is `.inTrash`; error 4 with a stored volume path that is not mounted is `.volumeOffline`; every other failure is `.missing`. `Shelf.resolving(with:maker:isMounted:) -> ResolvedShelf { statuses: [UUID: ItemStatus], shelf: Shelf }` where stale items get a fresh bookmark and path. `SystemBookmarks` implements both ports with Foundation: create with `.withoutImplicitSecurityScope`; resolve with `[.withoutUI, .withoutMounting, .withoutImplicitStartAccessing]`; stored volume values from `URL.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey], fromBookmarkData:)`; identity from `.volumeUUIDStringKey` and `.fileIdentifierKey`; size from `.totalFileSizeKey` (folders: nil) |
| Acceptance | pure rule tests for every row of D-M5b-3; integration tests on `TempDir`: rename and move → present and stale, then refreshed (not stale on the next resolve); a move into a folder named `.Trash` inside the temporary folder → in the Trash (no real Trash is touched); delete → missing. No security-scoped option appears anywhere in `Sources/` (a test reads the options the system type uses) |
| Effort | M |

**Files:** create `Sources/ZivletShelfCore/BookmarkPorts.swift`, `Sources/ZivletShelfCore/ItemStatus.swift`,
`Sources/ZivletShelfCore/Shelf+Resolve.swift`, `Sources/ZivletShelfCore/SystemBookmarks.swift`,
`Tests/ZivletShelfCoreTests/ItemStatusTests.swift`, `Tests/ZivletShelfCoreTests/SystemBookmarksTests.swift`,
`Tests/ZivletShelfCoreTests/FakeBookmarks.swift`.

```swift
@Suite("Item status from a bookmark (D-M5b-3)")
struct ItemStatusTests {
    @Test func aResolvedPathInTheTrashIsInTheTrash() {
        let r = Resolution.resolved(path: "/Users/u/.Trash/a.txt", stale: true)
        #expect(ItemStatus.from(r, isMounted: { _ in true }) == .inTrash(path: "/Users/u/.Trash/a.txt"))
    }

    @Test func aMissingFileOnAnUnmountedVolumeIsOffline() {
        let r = Resolution.failed(code: 4, storedVolumePath: "/Volumes/Backup", storedVolumeName: "Backup")
        #expect(ItemStatus.from(r, isMounted: { _ in false }) == .volumeOffline(name: "Backup"))
    }

    @Test func aMissingFileOnAMountedVolumeIsMissing() {
        let r = Resolution.failed(code: 4, storedVolumePath: "/", storedVolumeName: "Macintosh HD")
        #expect(ItemStatus.from(r, isMounted: { _ in true }) == .missing)
    }
}

@Suite("System bookmarks on real files (D-M5b-2)")
struct SystemBookmarksTests {
    @Test func aRenamedAndMovedFileResolvesStaleThenFresh() throws {
        let dir = try TempDir()
        let file = try dir.file("a.txt", "x")
        let bookmarks = SystemBookmarks()
        let item = try ShelfFixtures.item(from: file, using: bookmarks)
        let moved = try dir.folder("other").appending(path: "a renamed.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        let first = Shelf.single(item).resolving(with: bookmarks, maker: bookmarks, isMounted: { _ in true })
        #expect(first.statuses[item.id] == .present(path: moved.path))
        let again = first.shelf.resolving(with: bookmarks, maker: bookmarks, isMounted: { _ in true })
        #expect(again.shelf == first.shelf)  // nothing stale the second time
    }

    @Test func theOptionsAreNeverSecurityScoped() {
        #expect(!SystemBookmarks.creationOptions.contains(.withSecurityScope))
        #expect(SystemBookmarks.creationOptions.contains(.withoutImplicitSecurityScope))
        #expect(SystemBookmarks.resolutionOptions == [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing])
    }
}
```

RED: `cannot find 'ItemStatus' in scope`. Commit `feat(shelf): resolve box items from bookmarks into present, in
the Trash, offline or missing`.

---

## Task A5 — `BoxStore`: schema 1, atomic, 0600, validation, damaged file

| Field | Value |
|---|---|
| Goal | `BoxStore(file:)` and `BoxStore.standard()` (`~/Library/Application Support/Zivlet/boxes.json`). On disk: `{ "schema": 1, "boxes": [...], "current": "<uuid>" }`. `load() -> BoxLoad` = `.empty` (no file) \| `.loaded(ShelfLibrary, dropped: Int)` (invalid items or boxes over the caps dropped and counted) \| `.damaged` (unreadable JSON: the file is moved aside to `boxes.damaged.json`, replacing an older one, and the library starts empty) \| `.newer(schema:)` (a schema above 1: the file is left untouched, the library starts empty and `save` throws `.wouldOverwriteNewer` until relaunch). `save(_:) throws(BoxStoreError)`: write to a temporary file created with mode 0600 in the same folder, then replace atomically; the folder is created with 0700. Every outcome other than `.loaded`/`.empty` logs one line through `os.Logger` (no names: counts and the schema number only) |
| Acceptance | tests below on `TempDir`; the saved file's `posixPermissions` is `0o600`; a round trip of a library with two boxes is equal; a schema-2 file is byte-for-byte unchanged after `load` and a refused `save` |
| Effort | S |

**Files:** create `Sources/ZivletShelfCore/BoxStore.swift`, `Sources/ZivletShelfCore/StoredLibrary.swift`,
`Tests/ZivletShelfCoreTests/BoxStoreTests.swift`.

```swift
@Suite("Box store (P2-141: boxes.json 0600, atomic, schema-versioned)")
struct BoxStoreTests {
    @Test func aSavedLibraryIsPrivateAndRoundTrips() throws {
        let dir = try TempDir()
        let store = BoxStore(file: dir.url.appending(path: "Zivlet/boxes.json"))
        let lib = try ShelfFixtures.libraryWithTwoBoxes()
        try store.save(lib)
        let mode = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(store.load() == .loaded(lib, dropped: 0))
    }

    @Test func unreadableJSONIsMovedAsideAndTheBoxStartsEmpty() throws {
        let dir = try TempDir()
        let store = BoxStore(file: try dir.file("boxes.json", "{not json"))
        #expect(store.load() == .damaged)
        #expect(FileManager.default.fileExists(atPath: dir.url.appending(path: "boxes.damaged.json").path))
    }

    @Test func aNewerSchemaIsNeverOverwritten() throws {
        let dir = try TempDir()
        let file = try dir.file("boxes.json", #"{"schema":2,"boxes":[]}"#)
        let store = BoxStore(file: file)
        #expect(store.load() == .newer(schema: 2))
        #expect(throws: BoxStoreError.wouldOverwriteNewer) { try store.save(ShelfLibrary()) }
        #expect(try String(contentsOf: file, encoding: .utf8) == #"{"schema":2,"boxes":[]}"#)
    }

    @Test func invalidItemsAreDroppedAndCounted() throws { /* one item with an empty bookmark among two */ }
}
```

RED: `cannot find 'BoxStore' in scope`. Commit `feat(shelf): store boxes in a private, schema-versioned
boxes.json`.

---

## Task A6 — Owned storage, auto-clear plans, storage budget

| Field | Value |
|---|---|
| Goal | `OwnedStorage(root:)` (`standard()` = `~/Library/Application Support/Zivlet/Box/`): `folder(for box:)`, `reserve(name:in:) throws(ShelfError) -> URL` (sanitised name, `name 2.txt` on a clash, always inside the box folder: a name that resolves outside is refused), `bytes(in:)`, `allBytes()`. `AutoClear = .off \| .afterLeaving \| .after24Hours` and the pure `AutoClearPlan.items(in:policy:now:left:) -> Set<UUID>` (after leaving: items whose drag-out or move finished; after 24 h: items added more than 24 h before `now`). `StorageBudget.warnBytes = 2_000_000_000` (OWN-APP-3, decimal like Finder) and `isOverWarning(_:)`. `Trashing` port (`trash(_:) throws`) with the system implementation `FileManager.trashItem`; owned copies are trashed, never unlinked |
| Acceptance | tests below; nothing is written outside `TempDir` |
| Effort | S |

**Files:** create `Sources/ZivletShelfCore/OwnedStorage.swift`, `Sources/ZivletShelfCore/AutoClear.swift`,
`Sources/ZivletShelfCore/StorageBudget.swift`, `Sources/ZivletShelfCore/Trashing.swift`,
`Tests/ZivletShelfCoreTests/OwnedStorageTests.swift`, `Tests/ZivletShelfCoreTests/AutoClearTests.swift`.

```swift
@Suite("Owned copies and auto-clear (P2-141, OWN-APP-3)")
struct OwnedStorageTests {
    @Test func aClashGetsTheNextFreeName() throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let box = UUID()
        let first = try storage.reserve(name: "Clipping.txt", in: box)
        try Data().write(to: first)
        #expect(try storage.reserve(name: "Clipping.txt", in: box).lastPathComponent == "Clipping 2.txt")
    }

    @Test(arguments: ["../escape.txt", "/etc/passwd", "a/../../b"])
    func aNameCannotLeaveTheBoxFolder(_ name: String) throws {
        let storage = OwnedStorage(root: try TempDir().url)
        let url = try? storage.reserve(name: name, in: UUID())
        #expect(url == nil || url!.path.hasPrefix(storage.root.path))
    }

    @Test func after24HoursPicksOnlyOldItems() throws {
        let shelf = try ShelfFixtures.shelf(addedAt: [.t0, .t0.addingTimeInterval(23 * 3600)])
        let plan = AutoClearPlan.items(in: shelf, policy: .after24Hours, now: .t0.addingTimeInterval(24 * 3600 + 1), left: [])
        #expect(plan == [shelf.items[0].id])
    }

    @Test func theWarningStartsAt2GB() {
        #expect(!StorageBudget.isOverWarning(1_999_999_999) && StorageBudget.isOverWarning(2_000_000_000))
    }
}
```

RED: `cannot find 'OwnedStorage' in scope`. Commit `feat(shelf): add owned-copy storage, auto-clear plans and the
2 GB storage warning`.

---

## Task A7 — Settings group `box` (D-M5b-19)

| Field | Value |
|---|---|
| Goal | `BoxGroup { trayWhileDragging = true, shakeToOpen = false, autoClear: BoxAutoClearChoice = .off, dropsGo: BoxDropsChoice = .recentBox }` in `ZivletSettings` (its own enums: the settings module does not depend on `ZivletShelfCore`; the app maps them). Stored under its own key in the pattern of the `hud` group, schema 1; an unknown stored value falls back to the default with a log line; `Settings.box`; Copy Diagnostics lists the four values (they hold no names) |
| Acceptance | defaults, round trip, invalid stored value → default, diagnostics JSON contains the group |
| Effort | S |

**Files:** create `Sources/ZivletSettings/BoxGroup.swift`; modify `Sources/ZivletSettings/Settings.swift`,
`Sources/ZivletSettings/SettingsStore.swift`, `Sources/ZivletSettings/SettingsCoding.swift` (if the group needs
custom coding), `Tests/ZivletSettingsTests/SettingsStoreTests.swift` (new `@Suite("Box settings (D-M5b-19)")`).

```swift
@Suite("Box settings (D-M5b-19)")
struct BoxSettingsTests {
    @Test func defaultsFollowTheOwnersChoices() {
        let box = Settings.defaults.box
        #expect(box.trayWhileDragging && !box.shakeToOpen && box.autoClear == .off && box.dropsGo == .recentBox)
    }

    @Test func anUnknownStoredValueFallsBackToTheDefault() throws {
        let store = try SettingsStoreFixture.with(raw: ["box": #"{"schema":1,"autoClear":"sometimes"}"#])
        #expect(store.current.box.autoClear == .off)
    }
}
```

RED: `value of type 'Settings' has no member 'box'`. Commit `feat(settings): add the Drop Box settings group`.

---

## Task A8 — `ShakeDetector` and synthetic drag support (NB2, D-M5b-15)

| Field | Value |
|---|---|
| Goal | Pure `ShakeDetector` in `ZivletTrigger`: `Config { reversals = 4, minAmplitude = 30, window = 600 ms, cooldown = 300 ms }`; `observing(_ sample: InputSample) -> (ShakeDetector, fired: Bool)` counts horizontal reversals whose swing from the last turning point is ≥ `minAmplitude`, fires once when `reversals` fall inside `window`, then stays latched until `reset()` (the drag ended); `wheelHidden(at:)` blocks firing for `cooldown`. New test-support target `DragTraceSupport` (deps `ZivletTrigger`, `ZivletCore`, `TestSupport`; `strict`) with `SyntheticDrags`, seeded by `SplitMix64`: shakes (3–6 Hz, ±40–120 pt), straight, curved, hesitate-and-correct, 1 Hz wiggle, 8 Hz ±10 pt tremor, at 120 Hz |
| Acceptance | 500 of 500 synthetic shakes fire; 0 of 500 for each of the five non-shake kinds; a shake within 300 ms of `wheelHidden` does not fire; after firing, a second shake in the same drag does not fire again. An env-gated test reads recorded traces when `ZIVLET_DRAG_TRACES` names a folder (D3 format) and expects 0 shakes in every `normal` trace — the owner's acceptance, not run in CI |
| Effort | S |

**Files:** create `Sources/ZivletTrigger/ShakeDetector.swift`, `Tests/DragTraceSupport/SyntheticDrags.swift`,
`Tests/ZivletTriggerTests/ShakeDetectorTests.swift`; modify `Package.swift` (support target; `ZivletTriggerTests`
gains it).

```swift
@Suite("Shake detector (P2-141, D-M5b-15)")
struct ShakeDetectorTests {
    @Test func syntheticShakesFire() {
        var rng = SplitMix64(seed: 141)
        let fired = (0..<500).filter { _ in ShakeDetector.fires(on: SyntheticDrags.shake(&rng)) }
        #expect(fired.count == 500)
    }

    @Test(arguments: SyntheticDrags.NonShake.allCases)
    func ordinaryDragsDoNot(_ kind: SyntheticDrags.NonShake) {
        var rng = SplitMix64(seed: 55)
        #expect((0..<500).allSatisfy { _ in !ShakeDetector.fires(on: SyntheticDrags.trace(kind, &rng)) })
    }

    @Test func nothingFiresJustAfterTheWheelCloses() {
        var rng = SplitMix64(seed: 3)
        let samples = SyntheticDrags.shake(&rng)
        let detector = ShakeDetector().wheelHidden(at: samples[0].uptime)
        #expect(!detector.fires(on: samples))
    }
}
```

RED: `cannot find 'ShakeDetector' in scope`. Commit `feat(trigger): detect a shake during a file drag (opt-in)`.

---

## Task A9 — `TriggerHost.onLiveSample` and `onDragEnded` (D-M5b-16)

| Field | Value |
|---|---|
| Goal | `TriggerHost` hands each sample it steps while the machine is in `.live` to `onLiveSample: (InputSample) -> Void`, after stepping, and calls `onDragEnded: () -> Void` once when a live or wheel drag goes back to idle. Nothing is handed out in `pressed`, `detecting`, `passive`, `wheel` or `releasing`. No new monitor and no new permission: these are the samples the host already takes |
| Acceptance | `TriggerHostTests` with the existing `HostRig` and fakes (`TriggerFakes.swift`): samples reach the hook only while live; `onDragEnded` fires once per drag; after `stop()` (Pause) nothing reaches the hooks |
| Effort | S |

**Files:** modify `Sources/ZivletTriggerHost/TriggerHost.swift`; create
`Tests/ZivletTriggerHostTests/TriggerHostLiveSampleTests.swift`.

```swift
@Suite("Live samples for the tray and shake (D-M5b-16)")
@MainActor
struct TriggerHostLiveSampleTests {
    @Test func onlyLiveSamplesAreHandedOut() async throws {
        let rig = HostRig()
        var seen: [Duration] = []
        rig.host.onLiveSample = { seen.append($0.uptime) }
        await rig.startFileDrag()                          // mouse-down 0 ms, drag 10 ms, file types 18 ms: live
        rig.event(.frame, at: 30)
        rig.event(.frame, at: 60, mods: .command)          // the edge shows the wheel (after the 40 ms debounce)
        rig.event(.frame, at: 90)
        #expect(seen.contains(.milliseconds(30)) && !seen.contains(.milliseconds(90)))
    }

    @Test func dragEndIsReportedOnce() async throws { /* mouse up after live: one call */ }
    @Test func pauseStopsTheHooks() async throws { /* host.stop(); frames → no calls */ }
}
```

RED: `value of type 'TriggerHost' has no member 'onLiveSample'`. Commit `feat(trigger): hand live drag samples to
the tray and the shake detector`.

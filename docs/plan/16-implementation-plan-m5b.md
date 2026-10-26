# 16 — M5b implementation plan: the notch Drop Box (TDD)

Date: 2026-10-26. Status: ready to execute after the owner reads it. Branch: `m5b`, made from `main` at `0ef22d6`.
Look: [design/19c-drop-box-look](../design/19c-drop-box-look.md). Behaviour: [design/17e-app](../design/17e-app.md)
§2 and §2a.5; how the tray plugs into the island: [design/19-notch](../design/19-notch.md) §8. Acceptance: the 05
rows P2-141, P2-55 (§9.1 and §9.5), P2-142, P2-143 and the rest of P2-197. Decisions: [00-decisions](../design/00-decisions.md)
OWN-APP-1…3, OWN-PLAN-3, OWN-UI-1…5. The sketch this plan grows from is [12](12-implementation-plan-m5a-notch.md) §9
(NB1–NB8).

This file is the index: verification status, scope, the gap audit, the prototypes, decisions, streams and order,
conventions, exit rows, owner steps and risks. The tasks are in six parts, each under 800 lines:

| Part | Stream | Tasks |
|---|---|---|
| [16a](16a-m5b-shelf-core.md) | **A** — NB1 shelf core, NB2 shake | A0 baseline · A1 module · A2 item · A3 shelf and library · A4 bookmarks and item status · A5 store · A6 owned copies, auto-clear, storage · A7 settings group · A8 shake detector · A9 live-sample hook |
| [16b](16b-m5b-drop-box-panel.md) | **B** — NB3 Drop Box panel | B1 module, shared drag source · B2 presentation and dock · B3 tokens and contrast · B4 panel · B5 thumbnails · B6 views · B7 intake · B8 controller, restore · B9 BOX slice, menu, settings rows, wiring · B10 debug previews |
| [16c](16c-m5b-bulk-actions.md) | **C** — NB4 bulk actions | C1 targets · C2 Share · C3 AirDrop, Copy, Copy Paths · C4 Move to · C5 Copy to and its undo · C6 Remove, Trash, Clear, Locate · C7 storage and auto-clear · C8 Convert all · C9 Zip deferred |
| [16d](16d-m5b-proximity.md) | **D** (1 of 2) — NB5 proximity, recorder, replay | D1 `NotchProximity` · D2 tray zone · D3 trace model and synthetic traces · D4 replay harness · D5 tuning tool · D6 debug recorder · D7 pre-drop reads (C4) |
| [16e](16e-m5b-tray.md) | **D** (2 of 2) — NB6 tray client, NB7 tray drop | D8 `.dropTarget` and `.sensor` · D9 drop plumbing in the island · D10 tray client · D11 tray drop and compact view · D12 app wiring · D13 timing |
| [16f](16f-m5b-qa-exit.md) | **E** — NB8 QA, exit, record | E1 QA list · E2 exit runner · E3 every box and tray state on screen · E4 box demo and relaunch · E5 idle CPU · E6 exit run and record |

Naming: as in plan 12 (OP-1, still open), "M5b" here means the notch Drop Box slice of 05's beta-0.5 milestone, not
05 §9.2's M5b (beta 0.6). 05 is not changed by this plan.

Clean room: unchanged. No code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch or
shelf app; prior art is described in 17e §2.2 and §2a.2 in our own words. Every string quoted in these parts is
Zivlet's own; new ones are marked *new* in 19c §5.

---

## 0. Verification status of this plan

| Check | Result |
|---|---|
| Baseline | `nice -n 10 make test` on `m5b` at `0ef22d6` (this session): exit 0, 15 test bundles, **1240 tests**, all passed. `make lint`, `make coverage`, `make app` and the release gates were **not** re-run for this plan (docs only); task A0 runs `make test lint` before any code |
| Code read | `ZivletNotchCore/*` (arbiter, request, surface, machine and its holds, layout metrics, events), `ZivletNotch/*` (`IslandClient`, `IslandHosts`, `IslandPanel`), `ZivletTrigger` (`TriggerMachine`, `+Live`, `TriggerState`, `TriggerTypes`, `TriggerTrace`), `ZivletTriggerHost` (`TriggerHost`, `FrameSampler`, `TriggerPorts`, `SystemInputReader`), `ZivletActions` (`ActionService`, `ActionError`, `AirDropAction`, `MoveExecutor`), `ZivletRuntime/UndoHistory.swift`, `ZivletUI/HUD` (`HUDPresenter`, `ThumbnailLoader`, `FileDragSource`, `HUDWindow`), `ZivletWheel/DragPayload.swift` (the wheel's pre-drop payload probe), `ZivletCore/Catalog/ActionID.swift`, `ZivletSettings/Settings.swift`, `App/ActionWiring.swift`, `App/IslandWiring.swift`, `App/AppDelegate.swift`, `App/IslandShots.swift`, `App/SettingsWiring.swift`, `Package.swift`, `Makefile`, `Scripts/m5a-exit.sh`, `Scripts/demo-notch-states.sh`, `Scripts/check-release-paths.sh`, `Scripts/coverage.sh`, test fixtures in `Tests/NotchTestSupport` |
| Prototypes | Run on this Mac on 2026-10-26, outside the repository (§3): non-activating panel with drops, promises and a 200-item drag payload; island-level drag registration and hit tests; Quick Look thumbnails; the share picker and AirDrop; bookmarks in Downloads, iCloud Drive and a disk-image volume, with the TCC log. Plus a synthetic grid search for the proximity rule |
| Code in the parts | Swift in the parts is specification-grade and was **not** compiled. Each RED step names the expected compile error or assertion, not a recorded one |
| Hardware | 14-inch MacBook Pro (Mac14,9), macOS 27.0 (26A428), display 1800 × 1169 pt, the M5a recorded fixture's values (safe-area top 38, auxiliary areas 790 wide at x 0 and x 1010) |

---

## 1. Scope

| In M5b | Row | Stream |
|---|---|---|
| Shelf core: items, boxes, bookmarks, store, owned copies, auto-clear plans | P2-141 | A |
| Shake detector, opt-in | P2-141 | A |
| Drop Box panel replacing Float; menu "Show Drop Box"; wheel `BOX` (`tray.full`); restore after relaunch | P2-55 (§9.1, §9.5) | B |
| Bulk actions: Share, AirDrop, Copy, Copy Paths, Move to, Copy to, Convert all, Remove, Move to Trash, Clear, failures, storage | P2-142 | C |
| `NotchProximity`, the DEBUG drag-trace recorder, the replay harness; the pre-drop-read TCC/iCloud question | P2-197 remainder | D |
| Tray client: `.tray` requests, `dropTarget`, drag registration only while asked, the wheel wins | P2-143 | D |
| Tray drop into the current box; compact view as the tray's expanded content; full panel one click away | P2-143 | D |
| QA rows, exit runner, every-state demo, owner steps, record | — | E |

Not in M5b: **Zip** (P2-142's Zip button needs P2-111 EngineArchive, which is not built; G-M5b-1); the picker at
the notch (last phase); a global hotkey for the box (KeyboardShortcuts is planned but not in the repo); Services
"Add to Drop Box" and `zivlet box` (P3); shake on by default (P4-111, after 500 recorded normal drags); G-M5a-1 (the
fast-progress CPU item stays open and untouched).

---

## 2. Gap audit: what exists today and what is missing

Read from the code on `m5b` at `0ef22d6` and checked with the baseline run (§0). "Task" is where the gap is closed.

### 2.1 By acceptance clause

| Row | Clause | Exists today | Missing | Task |
|---|---|---|---|---|
| P2-141 | Immutable `Shelf`/`ShelfItem` | nothing; no `ZivletShelfCore` module | the module, both values, every edit returning a new value | A1–A3 |
| P2-141 | bookmark `.withoutImplicitSecurityScope`, resolve with `.withoutImplicitStartAccessing` | no bookmark code anywhere in `Sources/` | creation and resolution behind a port; prototype §3 (e) confirms the options and their cost | A4 |
| P2-141 | de-dup by file identity | — | identity from `fileResourceIdentifier` and the volume (prototype read both) | A3 |
| P2-141 | Trash path = missing | — | prototype: a trashed file's bookmark resolves **into** the Trash with `stale: true`, so the status rule must look at the path | A4 |
| P2-141 | `boxes.json` 0600, atomic, schema-versioned | `UndoStore` and `JobRecordStore` write atomically, but set no 0600 mode and have no version field | a store with a version, 0600, validation on load, a damaged-file rule | A5 |
| P2-141 | lazy resolve | — | resolution on show, never at launch | A4, B8 |
| P2-141 | owned copies only for promise and clipping content, under `Box/<id>/` | — | owned storage, names, path checks | A6, B7 |
| P2-141 | auto-clear plans | — | pure plans for off / after leaving / after 24 h | A6, C7 |
| P2-141 | shake: 4 reversals ≥ 30 pt in 0.6 s, opt-in, 0 false positives on recorded non-shake traces | the trigger host samples the pointer at display rate during a live file drag (`FrameSampler`, `InputSample` is `Codable` with `location`); **no** recorded traces exist in the repository (trigger tests script their samples) | the detector, a hook that hands live samples out of `TriggerHost`, a setting; recorded traces are an owner step | A7–A9, OS-M5b-1 |
| P2-55 §9.1 | non-activating floating panel(s), all Spaces | `HUDWindow` and `IslandPanel` show the pattern (borderless, non-activating, `becomesKeyOnlyIfNeeded`) | `BoxPanel` at `.floating`; prototype (a): showing it left the frontmost app unchanged | B4 |
| P2-55 §9.1 | edge dock (attach 28 / detach 48) or free | — | pure dock rules | B2 |
| P2-55 §9.1 | compact/expanded, icons/list | — | presentation machine, views | B2, B6 |
| P2-55 §9.1 | QL thumbnails and Quick Look | `ThumbnailLoader` (one 64 pt thumbnail off the main thread, for the HUD card) | a cache with a concurrency limit and type icons; Quick Look from a non-activating panel (not prototyped; QA row) | B5, B8 |
| P2-55 §9.1 | drag-out | `FileDragSource` (one dragging item per file) — internal to `ZivletUI` | sharing it with the box (move to `ZivletActions`); prototype (a): a 200-item payload builds and reads back 200 URLs; a real drag to Finder was not run | B1, B8, QA |
| P2-55 §9.1 | marquee, type-to-select (0.8 s reset), context menu | — | selection model and key map | B8 |
| P2-55 §9.1 | "new vs add to existing" setting | — | `box.dropsGo` (most recent by default, OWN-APP-1) | A7, B9 |
| P2-55 §9.1 | missing files greyed with "Locate…" | — | Attention state, badges, Locate | B2, B6, C6 |
| P2-55 §9.1, §9.5 | restored after relaunch | — | load on launch, frame and dock restored, items resolved on show | B8, E4 |
| P2-55 §9.5 | Float becomes the Drop Box (states, dock, grid/list, QL, keyboard, AX) on top of P2-141 | `ActionID.pinFloating` exists; its slice is hidden (`ActionWiring.unavailableActions = [.pinFloating]`) and a stray request answers "Float arrives in a later version." | everything in Stream B | B1–B10 |
| P2-55 §9.5 | wheel label `BOX`, `tray.full`; `ActionID.pinFloating` raw value kept | label "FLOAT", symbol `pin` (`ToolCatalogTests` asserts the labels) | label, symbol, service path, slice shown | B9 |
| P2-55 §9.5 | drag-out of 200 items works | see drag-out | real 200-item drag to Finder | B8, QA B-rows |
| P2-55 §9.5 | missing → Attention with Locate…; Trash path counts as missing | — | see above | A4, B2, C6 |
| P2-142 | Share (`NSSharingServicePicker`) | — | prototype (d): the picker opens from the non-activating panel and the app stays inactive; AirDrop is in the picker's own top row, not in the delegate's proposed list | C2 |
| P2-142 | AirDrop | `AirDropAction` (`canPerform` first, then the system sheet) | box entry point | C3 |
| P2-142 | Copy (URLs), Copy paths | `ClipboardAction.copyItems`, `copyPaths(shellQuoted:)` | box entry point | C3 |
| P2-142 | Move to… (one undo entry) | `MovePanel`, `MoveSurvey`, `MoveExecutor` (rename, or copy-verify-trash), `UndoHistory` records one batch of `UndoMove` | box references follow the moved files | C4 |
| P2-142 | Copy to… (one undo entry) | — `MoveExecutor` always trashes after a cross-volume copy; `UndoLog` knows only moves | a copy mode and a copy undo entry (undo puts the copies in the Trash) | C5 |
| P2-142 | Zip via coordinator | — EngineArchive (P2-111) is not built | **deferred**, recorded (G-M5b-1) | C9 |
| P2-142 | Convert all (drag out with ⇧) | the trigger allows drags that start in Zivlet's own windows (design 14 §1); not tested from a box | a test that a drag from the box opens the wheel; QA row | C8 |
| P2-142 | Remove, Move to Trash (confirm > 1), Clear (10 s undo toast) | action toasts with Undo through `ActionPresenter` (`ActionHUD`, `NotchHUD`), lingers 1.5 s and 4 s | inline confirmation; a 10 s linger | C6 |
| P2-142 | per-item failure list | `ActionCard(title:lines:)` and "and 3 more" | box failures mapped to lines | C1, C6 |
| P2-142 | storage line + "Empty box storage" | — | storage total, warning at 2 GB (OWN-APP-3), empty command | C7 |
| P2-143 | during a file drag, pure `NotchProximity` (sampler data, no permission) expands a tray | the sampler; `NotchGeometry.housing(of:)`; `IslandLayout.display(for:in:)` | the detector, the zone, the client, a `dropTarget` surface | D1, D2, D8, D10 |
| P2-143 | drop stashes into the current box | — | island drop plumbing; intake shared with the panel | D9, D11 |
| P2-143 | hover/click opens the tray later | hover with intent and grace exists in `IslandMachine` | a resting surface that takes hover (`.sensor`, D-BL10) | D8, D10 |
| P2-143 | above the menu bar on all Spaces incl. full screen | `IslandPanel`: `.statusBar`, `.fullScreenAuxiliary`, `.canJoinAllSpaces`; the M5a spike saw it in a full-screen Space | a real drag onto it in full screen (not run: QA row) | D9, QA T-rows |
| P2-143 | top-centre pill without a notch; per screen on externals | pill frames in `IslandLayout`; one host per display in `IslandHosts` | a zone per display, the pill drop target | D2, D12 |
| P2-143 | Reduce Motion → fade | `IslandMotion` | nothing new | — |
| P2-143 | never covers menu-bar items beyond the hover | the 6 pt rule for the collapsed tab (D-N3) | `.sensor` draws nothing; `.dropTarget` only during a near-notch drag | D8 |
| P2-143 | works alongside the wheel; the wheel drop wins | `wheelShown`/`wheelHidden` suppress hover in every machine | the tray withdraws and unregisters while the wheel shows | D9, D10 |
| P2-143 | P-N1 spike thresholds | — | provisional constants from synthetic traces (§3.6); recordings decide | D1, D4, OS-M5b-1 |
| P2-143 | 0 TCC prompts (TCC diff) | the M5a exit row X5 counts `preflight=no` requests | a Y row for the box demos | E2 |
| P2-197 | detection ≥ 95 % with 0 accidental opens over 200 recorded normal drags | — | recorder, replay harness, tuning tool; the recordings are an owner step and are **not** claimed here | D3–D6, OS-M5b-1 |
| P2-197 | TCC/iCloud behaviour of pre-drop reads (C4) | the trigger reads drag types only (`dragHasFileTypes`), but the wheel's payload probe (`DragPayloadReader`, M2) already reads the file URLs and four metadata keys (directory, package, size, local volume) of up to 512 dragged items **during the drag, before any drop** | prototype §3 (e): reads of that kind raised no prompt; the tray adds no new pre-drop read; content reads after relaunch are QA rows | D7, QA C4-rows |

### 2.2 By NB task (plan 12 §9)

| NB | Exists today | Missing | Stream / tasks |
|---|---|---|---|
| NB1 shelf core | `Rect2D` in `ZivletCore` for frames; atomic-write pattern in `UndoStore` | the whole module | A1–A7 |
| NB2 shake | live samples inside `TriggerHost` | detector, hook, setting, recorded traces | A8, A9 |
| NB3 Drop Box panel | panel pattern, drag source, thumbnail loader, the hidden `pinFloating` slice | module, presentation, views, intake, controller, menu, slice, restore | B1–B10 |
| NB4 bulk actions | AirDrop, Copy, Copy Paths, Move with undo, action toasts and cards | Share, Copy to with undo, Trash, Clear, storage, Convert-all test; Zip deferred | C1–C9 |
| NB5 proximity remainder | geometry and the recorded display fixture | detector, zone, trace model, recorder, replay, tuning tool, C4 answer | D1–D7 |
| NB6 tray client | arbiter with `.tray` (tested with fakes), `IslandHosts.register(_:as:)`, `wheelShown` | `.dropTarget`, `.sensor`, drop plumbing, client | D8–D10, D12 |
| NB7 tray drop and compact view | host surfaces per client | intake from the island, compact view, open-panel button | D11 |
| NB8 QA and exit | `qa/notch.md`, `m5a-exit.sh`, `demo-notch-states.sh` patterns | `qa/drop-box.md`, `m5b-exit.sh`, `demo-box-states.sh`, `demo-box.sh`, record | E1–E6 |

---

## 3. Prototype results (2026-10-26, outside the repository)

A throwaway AppKit program (Swift 6.4, macOS 27.0 SDK, `-target arm64-apple-macos26.0`), run from the shell and,
for the TCC question, as its own ad-hoc-signed app bundle launched with `open` so that TCC saw a new identity. No
synthetic pointer input was posted and no Space was switched: the Mac was in use, and a synthetic drag could also
have reached a running Zivlet. What needs a real drag is a QA row.

### 3.1 (a) Non-activating panel, drops, promises, 200 items out

| Check | Result |
|---|---|
| Show (`orderFrontRegardless`) | frontmost app unchanged (Terminal), Zivlet-like app not active, panel not key |
| `makeKey()` (what a click into the panel does) | panel key, frontmost app **still** unchanged; `NSApp.isActive` turned true. So keyboard input goes to the panel after a click, as designed (17e §2.3), without bringing the app forward |
| Registered types | file URL + the 3 file-promise types |
| Drop of 200 file URLs through the destination methods (fake dragging info on a private pasteboard) | 200 received in 39–52 ms |
| Log noise | reading file URLs from a pasteboard logged **one `sandbox_extension_consume failed: 1` line per URL** (400 for two reads of 200). The baseline test run shows the same lines. Harmless; noted so nobody chases it |
| File promises | `NSFilePromiseReceiver` objects read from the pasteboard (20 of 20, types seen); **receiving raised** `receivePromisedFiles… can only be called during -prepareForDragOperation:, -performDragOperation:, and -concludeDragOperation:` outside a real drag session. So promises go behind a port (D-M5b-5) and real promises are QA rows (Mail, Photos, Safari) |
| Drag-out payload for 200 items | 200 `NSDraggingItem`s built and a pasteboard written from them read back 200 URLs (30 ms). A real drag session to Finder was **not** run |

### 3.2 (b) Island-level drop target

| Check | Result |
|---|---|
| Registration on demand | 0 types at rest → 4 while "the tray asks" → 0 after withdrawing (`registerForDraggedTypes` / `unregisterDraggedTypes` on the content view) |
| Window order at the notch | a `.statusBar` panel (layer 25) is the top window inside the housing band (y 1165) and just below the menu bar (y 1111); beside it the menu bar (Window Server, layer 24) is on top |
| `ignoresMouseEvents` | `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` still returned the panel with `ignoresMouseEvents = true`: it is a geometric query, so it cannot tell how drags are routed |
| Real drag onto it; full-screen Space | **not run** (no synthetic input, no Space switch). The M5a spike already showed the island drawn in a full-screen Space; whether a drag is delivered to it there is QA row T4 |

### 3.3 (c) Quick Look thumbnails off the main thread

251 files (200 made: text, PNG, PDF, JSON; 51 media fixtures from `build/fixtures/small`), 64 pt at 2×,
`generateBestRepresentation` for each: all 251 returned (240 thumbnails, 11 icons), 0 callbacks on the main thread,
cold 1.08 s for all (first at 572 ms), warm 568 ms (first at 29 ms); the longest main-thread gap measured by a
60 Hz timer was **17.7 ms**; resident memory 48–74 MB afterwards. Not measured: 2,000 items, network volumes,
iCloud placeholders (the thumbnail of an evicted file may download it; QA row C4c).

### 3.4 (d) Share picker and AirDrop from a non-activating panel

`NSSharingServicePicker.show(relativeTo:of:preferredEdge:)` returned at once (370 ms on a loaded Mac) and showed
the system share popover above the button (AirDrop, Mail, Messages, Copy, Edit Extensions…). During and after it:
frontmost app unchanged, app not active, panel not key; `close()` (macOS 13+) dismissed it. The delegate's
`proposedSharingServices` held only Mail and Messages: AirDrop sits in the picker's own row. `standardShareMenuItem`
is "Share…". AirDrop `canPerform` was true for 3 and for 200 files. AirDrop's `perform` (its system sheet) was
**not** invoked.

### 3.5 (e) Bookmarks and the pre-drop-read TCC question (C4)

Run as a shell child (the terminal's TCC grants) for the mechanics, then as its own app bundle for TCC, with
`log show --predicate 'subsystem == "com.apple.TCC"'`. Files: one made in `~/Downloads`, one existing iCloud Drive
file that was **evicted** (not downloaded), one made on an APFS disk image attached with `-nobrowse` (ejectable,
not internal). Content was never read.

| Check | Result |
|---|---|
| Bookmark size | `.withoutImplicitSecurityScope`: 768 B (Downloads), 960 B (iCloud), 1,600 B (volume); default 744–2,144 B |
| Resolve 200× (`.withoutUI`, `.withoutMounting`, `.withoutImplicitStartAccessing`) | 4.3 ms, 5.6 ms, 9.1 ms |
| Renamed and moved | resolves to the new path, `stale: true` → refresh and save |
| Moved to the Trash | resolves to the item **in the Trash**, `stale: true` → must count as missing (path rule) |
| Deleted | error `NSCocoaErrorDomain 4` |
| Volume unmounted | the same error 4, but `URL.resourceValues(forKeys:fromBookmarkData:)` still gives the volume's name and path, so "volume not connected" can be told apart from "deleted" (D-M5b-3) |
| Evicted iCloud file | metadata, bookmark and resolve all worked; the file stayed "not downloaded" |
| **Pre-drop reads** (bundle identity): pasteboard types, item count and URL strings | no file-system access, and no TCC request of any kind |
| **Metadata reads** (bundle identity): `fileSize`, then bookmark `.withoutImplicitSecurityScope` and resolve | Downloads: only `preflight=yes` checks (`SystemPolicyDownloadsFolder`, answer "unknown", no prompt); iCloud file and the disk image: **no** TCC request at all. These are the kind of reads the wheel's payload probe already makes before every drop (resource values of up to 512 items), which is consistent with M5a's exit row X5 finding no prompt |
| **`.withSecurityScope` bookmark** of the Downloads file (bundle identity) | **a real prompt**: `AUTHREQ_PROMPTING`, `preflight=no`, `SystemPolicyDownloadsFolder` ("… would like to access files in your Downloads folder"). Hence D-M5b-2: Zivlet never makes security-scoped bookmarks. (The probe's prompt was closed by ending the system's alert process; it belonged to the throwaway bundle, not to Zivlet) |
| Not settled | content reads after a relaunch (Quick Look thumbnails of items in Downloads, Desktop, Documents or iCloud Drive); a real USB volume (TCC's removable-volume class; the disk image raised none); the real Finder drag pasteboard (the probe wrote its own); whether Zivlet already holds folder access from conversions that write next to the source (not checked). These are QA rows C4a–C4d and owner question OP-M5b-3 |

### 3.6 NB5: provisional proximity rule on synthetic traces

A scratch grid search on the recorded 14-inch geometry (housing x 790–1010, 38 pt, menu bar 39 pt), 120 Hz,
minimum-jerk paths with overshoot, tremor and a dwell at the end. Normal drags: 120 to anywhere, 40 to targets just
under the menu bar near the centre (the hard case), 20 to the menu bar beside the housing, 20 to the Dock.
Notch-bound drags end on or near the housing and wait 0.12–0.6 s. Five independent sets of 200 + 50.

| Assumed endpoint spread of notch-bound drags | Rule: zone = housing x ± 40 pt within the housing band, dwell 100 ms, speed ≤ 800 pt/s |
|---|---|
| uniform ± 150 pt around the centre (pessimistic) | detection 98–100 % per set; accidental opens 0, 0, 1, 1, 0 per 200 |
| Gaussian, SD 50 pt (Fitts-like) | detection 98–100 % per set; accidental opens 0 in all five sets |

The accidental opens came from drags that end on a status item within 40 pt of the housing. A 20 pt margin removed
them in the pessimistic case but dropped detection to 80–92 %. These numbers rest on made-up movement and are only a
starting point for D1; the owner's recordings (OS-M5b-1) decide.

---

## 4. Decisions

| ID | Decision | Why |
|---|---|---|
| D-M5b-1 | Two new modules: **`ZivletShelfCore`** (`strict`, Foundation only, depends on `ZivletCore`) and **`ZivletBox`** (`shell`: panel, views, intake, controller, tray client; depends on `ZivletShelfCore`, `ZivletActions`, `ZivletNotchCore`, `ZivletNotch`, `ZivletCore`). `ZivletActions` gains the bulk-action executors and the shared `FileDragSource`, no box views. `ZivletUI` and `App` stay the wiring layer | 17e and design 19 §8 put the panel and the tray in `ZivletActions`, but `ZivletActions` does not depend on `ZivletNotch` and has no views; a box module keeps the dependency direction and gets its own coverage line. Surface tokens (finish, scrim, outline) are reused from `ZivletNotch`, not copied |
| D-M5b-2 | Bookmarks are created with `.withoutImplicitSecurityScope` and resolved with `[.withoutUI, .withoutMounting, .withoutImplicitStartAccessing]`; Zivlet **never** creates `.withSecurityScope` bookmarks | §3.5: the security-scoped one raised a Downloads prompt; the other made only preflight checks |
| D-M5b-3 | Item status from a resolution: **present** (stale → refresh and save), **in the Trash** (a path component `.Trash` or `.Trashes`), **volume not connected** (error 4 while the bookmark's stored volume path is not mounted), **missing** (error 4 otherwise, or any other error) | §3.5: Trash resolves with `stale: true`; unmounted and deleted share error 4 |
| D-M5b-4 | **The tray and the panel add no pre-drop file read**: during a drag they use only the drag types (as the trigger does) and the pasteboard item count for "Add 3". No bookmark, thumbnail or resolution before `performDragOperation`. The wheel's existing payload probe (metadata of up to 512 items) is unchanged | §3.5: pasteboard reads make no TCC request and metadata reads made only preflight checks; nothing in M5b needs more before the drop |
| D-M5b-5 | File promises are received only inside `performDragOperation`, behind a `PromiseReceiving` port, into `Box/<box-id>/`; tests use a fake port | §3.1: AppKit raises outside a real session |
| D-M5b-6 | The arbiter ranks **visible** resting surfaces above the tray's invisible `.sensor`, then by client priority. A tray at rest never hides the HUD's progress; a tray drop target (visible) still beats the HUD | Today the highest-priority client wins whatever it rests on; a sensor that beat the HUD would hide every job while the box has items |
| D-M5b-7 | `ZivletNotch` stays file-agnostic: the host hands `NSDraggingInfo` to a client that adopts `IslandDropHandling`, and registers drag types on its content view only while the applied surface is `.dropTarget` | design 19 §8's constraint (no files, jobs or batches in the island modules); §3.2 shows registration on demand works |
| D-M5b-8 | The wheel wins: on `wheelShown` the tray withdraws its request and the host unregisters drag types at once; after `wheelHidden` it re-arms only on a new entry into the zone | P2-143 "wheel drop wins"; the wheel sits at `.popUpMenu` (101) above the island (25) anyway, but a drop into the tray during a wheel drag must be impossible, not unlikely |
| D-M5b-9 | `NotchProximity` provisional constants: margin 40 pt beside the housing, band = the housing's height from the display top, dwell 100 ms, speed ≤ 800 pt/s; on a display without a notch the pill's collapsed rectangle ± 40 pt inside the menu-bar band. One `Config` value; the zone comes from `IslandLayout.trayZone(on:)` | §3.6; values in one place so recordings change constants, not code |
| D-M5b-10 | The drag-trace recorder is **DEBUG-only** and opt-in (`-ZivletRecordDragTraces normal\|notch`): it writes timings, positions, button state and the display geometry, nothing about files, to `~/Library/Application Support/Zivlet/DragTraces/` (directory 0700, files 0600). `check-release-paths.sh` refuses the flag in a Release build | Recordings are needed (P2-197) but must never ship or leave the Mac unless the owner commits them |
| D-M5b-11 | **Zip is deferred**: no Zip button in M5b (not a disabled one); G-M5b-1 records it; P2-142 stays open for Zip | P2-111 EngineArchive is not built |
| D-M5b-12 | Confirmations are inline (19c D-BL9); no `NSAlert` in `ZivletBox` (Y9 checks) | Owner rule: no modal alerts in automation; fewer words |
| D-M5b-13 | Copy to… is `MoveExecutor` in a copy mode (copy, verify, claim the name; no Trash). Its undo puts the copies in the Trash if they are unchanged since the copy (stamp check, as Move's undo does). `UndoLog` gets schema 2 with a copy entry; schema-1 files decode | P2-142 asks one undo entry per batch for Copy to too |
| D-M5b-14 | Thumbnails: the type icon first (no file read), then Quick Look for visible cells only, at most 4 at a time, cached by item and modification date; after a relaunch nothing is read until the box or the tray is shown | §3.3; C4's open part is content reads after relaunch (QA C4b) |
| D-M5b-15 | Shake: opt-in (`box.shakeToOpen`, default off); 4 horizontal reversals of at least 30 pt within 0.6 s; only during a live file drag; 300 ms cooldown after the wheel hides | 05 P2-141; OWN-APP-2 |
| D-M5b-16 | The tray and shake ride on the trigger host's live samples, so Pause (which stops the trigger host) stops them too | `SettingsWiring` stops the host when paused; one switch for everything that watches drags |
| D-M5b-17 | Tray at rest: `.sensor` on notch displays while the box has items (19c D-BL10); hidden on pill displays, where the box is reached from the menu or the BOX slice | Nothing drawn at the notch until asked; OP-M5b-2 |
| D-M5b-18 | Current box = the most recent (OWN-APP-1); ⌥ on BOX makes a new box; at most 8 boxes and 2,000 items per box (validation caps); owned-copy warning at 2 GB (OWN-APP-3) | 17e §2.3 |
| D-M5b-19 | Settings group `box` (schema 1): `trayWhileDragging` (on), `shakeToOpen` (off), `autoClear` (off), `dropsGo` (recent box) | the four choices 17e and the owner named; nothing else |
| D-M5b-20 | DEBUG launch flags for demos and screenshots: `-ZivletBoxPreview <state>`, `-ZivletTrayPreview <state>`, `-ZivletBoxDemo <folder>`; all refused by `check-release-paths.sh` | the plan 14 D-ND3 pattern |
| D-M5b-21 | The Clear toast offers Undo for 10 s: `ActionResult.done` gains an optional linger, honoured by both presenters | P2-142; today's undo toast lingers 4 s |
| D-M5b-22 | The 19b content tokens (`NotchLook`, `NotchInk`) move from `ZivletUI` into `ZivletNotch` as `IslandContentLook` and `IslandInk`; `ZivletUI` keeps its names through typealiases; `ZivletBox` adds only `BoxLook` | One set of spacing, type and ink for the island and the box; `ZivletBox` cannot import `ZivletUI`, and a copy would drift |

---

## 5. Streams, order and estimate

Streams run in this order: **A → B → C → D → E**. Inside D, D1–D7 (16d) come before D8–D13 (16e). A9 and D2 can
be done any time after A0. Each task ends green and committed. Sizes are 05 §1.1 sizes (S ≤ 1 day, M 2–4 days, one
engineer; ESTIMATE).

| Task | Title | Module(s) | Depends on | Size | Commit |
|---|---|---|---|---|---|
| A0 | Baseline gates | — | — | S | none |
| A1 | `ZivletShelfCore` module, test target, coverage gate | Package, ShelfCore | A0 | S | `chore(shelf)` |
| A2 | `ShelfItem`, ownership, identity, validation | ShelfCore | A1 | S | `feat(shelf)` |
| A3 | `Shelf`, `ShelfLibrary`: add with de-dup, remove, reorder, current box, caps, totals | ShelfCore | A2 | M | `feat(shelf)` |
| A4 | Bookmark port, system bookmarks, item status, refresh | ShelfCore | A3 | M | `feat(shelf)` |
| A5 | `BoxStore`: schema 1, atomic, 0600, validation, damaged file | ShelfCore | A3 | S | `feat(shelf)` |
| A6 | Owned storage, auto-clear plans, storage budget | ShelfCore | A3 | S | `feat(shelf)` |
| A7 | Settings group `box` | Settings | A0 | S | `feat(settings)` |
| A8 | `ShakeDetector`, synthetic trace support | Trigger, tests | A0 | S | `feat(trigger)` |
| A9 | `TriggerHost.onLiveSample` | TriggerHost | A0 | S | `feat(trigger)` |
| B1 | `ZivletBox` module; `FileDragSource` moves to `ZivletActions` | Package, Box, Actions, UI | A1 | S | `chore(box)`, `refactor(actions)` |
| B2 | `BoxPresentation` machine, `DockSnapper`, frame clamping | ShelfCore | A3 | M | `feat(shelf)` |
| B3 | Shared 19b tokens move to `ZivletNotch`; box tokens, finish, contrast, symbols | Notch, UI, Box | B1 | S | `refactor(notch)`, `feat(box)` |
| B4 | `BoxPanel` | Box | B1 | S | `feat(box)` |
| B5 | `ThumbnailCache`, type icons | Box | B1 | S | `feat(box)` |
| B6 | Views: header, grid, list, cells, bar, tab, collapsed, empty, confirm, attention | Box | B2, B3, B5 | M | `feat(box)` |
| B7 | Intake: drop view, URL validation, promises port, clippings | Box | A6, B1 | M | `feat(box)` |
| B8 | `BoxController`: add, restore, selection, keys, Quick Look, drag-out | Box | A4, A5, B4, B6, B7 | M | `feat(box)` |
| B9 | BOX slice, menu command, Settings rows, app wiring | Core, Actions, UI, App | B8, A7 | M | `feat(actions)`, `feat(ui)`, `feat(app)` |
| B10 | Box debug previews; release refusal | App, Scripts | B9 | S | `feat(app)`, `test(scripts)` |
| C1 | `BulkTargets`: selection or all, missing items as failures | ShelfCore | A4 | S | `feat(shelf)` |
| C2 | Share picker port | Actions, Box | B8 | S | `feat(actions)` |
| C3 | AirDrop, Copy, Copy Paths from the box | Actions, Box | C1 | S | `feat(box)` |
| C4 | Move to…; references follow | Actions, ShelfCore, Box | C1 | S | `feat(box)` |
| C5 | Copy to…: copy mode, undo schema 2 | Actions, Runtime, Box | C4 | M | `feat(runtime)`, `feat(actions)` |
| C6 | Remove, Trash (inline confirm), Clear (10 s undo), Locate…, Remove missing | Box, Actions, UI | C1 | M | `feat(box)`, `feat(ui)` |
| C7 | Storage line, Empty box storage, auto-clear runs | Box, UI | A6, C6 | S | `feat(box)` |
| C8 | Convert all: a drag from the box opens the wheel | Box, TriggerHost tests | B8 | S | `test(box)` |
| C9 | Zip deferred: no button, recorded | Box, docs | C3 | S | `test(box)` |
| D1 | `NotchProximity` | Trigger | A9 | S | `feat(trigger)` |
| D2 | `IslandLayout.trayZone(on:)` | NotchCore | A0 | S | `feat(notch)` |
| D3 | `DragTrace` model; synthetic generator and evaluator | Trigger, tests | D1, D2 | M | `feat(trigger)`, `test(trigger)` |
| D4 | Replay harness; `make drag-replay` | tests, Makefile | D3 | S | `test(trigger)` |
| D5 | `zivlet-traces` tuning tool | Package (dev tool) | D3 | S | `feat(tools)` |
| D6 | DEBUG recorder | TriggerHost, App, Scripts | A9, D3 | S | `feat(app)` |
| D7 | Pre-drop reads stay on the pasteboard | Box | B7 | S | `test(box)` |
| D8 | `.dropTarget`, `.sensor`; arbiter ranking | NotchCore | D2 | M | `feat(notch)` |
| D9 | Island drop plumbing | Notch | D8 | M | `feat(notch)` |
| D10 | `TrayClient` | Box | D1, D9, B8 | M | `feat(box)` |
| D11 | Tray drop → current box; compact view; open panel | Box | D10 | S | `feat(box)` |
| D12 | App wiring: register, samples, zones, wheel, previews | App | D10, D11, A9 | M | `feat(app)` |
| D13 | Tray timing ≤ 50 ms | Box tests | D12 | S | `test(box)` |
| E1 | `docs/plan/qa/drop-box.md` | docs | B9, D12 | S | `docs` |
| E2 | `Scripts/m5b-exit.sh` and its test | Scripts | E1 | S | `test(scripts)` |
| E3 | `Scripts/demo-box-states.sh` (every state) | Scripts | B10, D12 | S | `test(scripts)` |
| E4 | `Scripts/demo-box.sh` (add, relaunch, restored) | Scripts, App | B10 | S | `test(scripts)` |
| E5 | Idle CPU rows for the box and the tray | Scripts | E4 | S | `test(scripts)` |
| E6 | Exit run, owner list, `17-m5b-record.md` | docs | all | S | `docs` |

Estimate (ESTIMATE): 14 M and 34 S tasks. The 05 tally (§9.10: S 1 d, M 3 d, L 7.5 d) gives about 24
engineer-days for the five rows (P2-141 M, P2-55 L, P2-142 M, P2-143 L, P2-197 M). Most S tasks here are half a
day, so at S 0.5 d and M 2–3 d the split sums to **about 45–60 engineer-days**. It names work the 05 rows folded in
or did not see: the island changes (D8, D9), the recorder, replay harness and tuning tool, the undo schema, and
four scripts. Expect more than 05 says. For one agent in one session, take the tasks in the order of the table and
stop at the end of a task if the session must end.

---

## 6. Conventions

| Item | Rule |
|---|---|
| Environment | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before every `swift`, `xcodebuild`, `make`. Prefix heavy commands with `nice -n 10`; long ones run in the background. Never a clean `make vendor` rebuild |
| TDD | Each task: write the failing test → run it and see the stated failure → implement the minimum → green → refactor → commit. Refactors (B1's move) keep existing tests green before and after instead |
| Commands per task | RED/GREEN: `cd Packages/ZivletKit && nice -n 10 swift test --filter <Suite>`; then `nice -n 10 make test lint`; `nice -n 10 make coverage` when a gated module changed; `nice -n 10 make app` after B1, B9, D12 |
| Gates (M5b exit) | `make test`, `make lint`, `make coverage` (80 % per module; **16 modules** after B1), `make app`, `make release-check`, `make licence-gate`, `make script-test` (needs the media stage: run `make release-check` first in a fresh clone), the `Scripts/m5a-exit.sh` rows and the new `Scripts/m5b-exit.sh` rows |
| Commits | Conventional, `git commit -s`, **no** `Co-Authored-By`; scopes `shelf`, `box`, `trigger`, `notch`, `actions`, `runtime`, `settings`, `ui`, `app`, `tools`, `scripts`, `docs`. Only on `m5b`; never on `main`, never pushed, history never rewritten |
| Code rules | Immutable values (edits return new values), files < 800 lines (aim 200–400), functions < 50 lines, nesting ≤ 4, no `print` (dev tools write through `FileHandle`), typed errors with Zivlet's own copy, validation at boundaries: file URLs from drops, bookmarks and `boxes.json` on load, trace JSON, settings |
| Tests | Swift Testing (`@Suite`, `@Test`, `#expect`). Shell tests keep panels off screen (x −5000) as the island tests do. File-system tests use `TestSupport.TempDir`; nothing outside temporary folders |
| Launching the app | Quit any Zivlet you launch with `osascript -e 'quit app "Zivlet"'`. Never trigger a modal alert in the running app during automation |
| Screenshots | Only with the screen awake: check `ioreg -n Root -d1 -a \| grep -i CGSSessionScreenIsLocked` first; if locked, skip and say so. Frame-timing tests can fail while locked: rerun once by name. Demo captures wait a fixed time, so under load rerun once before calling a missing surface a defect |
| Deleting | Only what the task created, with literal absolute paths (the rm safety check refuses `rm -rf "$VAR/..."`). Never user data |
| Public repo | No personal paths, scratch paths or private research notes in tracked files or commit messages; describe prior art in our own words only; records say what was not measured, not seen or deferred |

---

## 7. Exit criteria (run by `Scripts/m5b-exit.sh`, task E2)

| Row | Check | Pass when |
|---|---|---|
| Y1 | `make test lint coverage app release-check licence-gate` | all pass; `ZivletShelfCore` and `ZivletBox` ≥ 80 % line coverage; no other gated module below 80 % |
| Y2 | `make script-test` | passes (after Y1's `release-check`, so the media stage exists) |
| Y3 | M5a regression | `Scripts/m5a-exit.sh --only X2,X3,X4,X5` passes (X6 stays with G-M5a-1 and is not an M5b row) |
| Y4 | `make box-demo` | the Debug app adds the demo files, shows the panel (`Box: shown`, `Box: items 4`), quits, relaunches and logs `Box: restored 4 items`; a screenshot of the panel is saved in `build/m5b-exit/` |
| Y5 | `make box-states` | every box and tray state in 19c §4 is captured into `build/box-states/`; over the white backdrop, white text at 0.8 is at least 4.5:1 on the panel, the docked tab and the tray drop target |
| Y6 | No TCC prompt | no tccd request with `preflight=no` attributed to Zivlet while Y3–Y5 ran (D-M5a-5) |
| Y7 | Synthetic replay | `make drag-replay` (synthetic sets on the recorded 14-inch fixture and on the constructed 1080p pill display): detection ≥ 95 % and 0 accidental opens in every set; shake: 0 false positives over the synthetic non-shake sets |
| Y8 | Idle CPU (Debug, minus a baseline) | `make box-idle`: box panel shown and still ≤ 0.1 %; tray at rest on its sensor ≤ 0.1 %; 120 s each by `Scripts/idle-cpu.sh`; Debug numbers, recorded as such |
| Y9 | Hygiene since `0ef22d6` | every commit signed off and without `Co-Authored-By`; no changed `.swift`/`.sh` file ≥ 800 lines; no personal or scratch path added; `ZivletShelfCore` imports only Foundation; no `NSAlert` in `ZivletBox` |

M5b is **code complete** when Y1–Y9 pass. It is **complete** when the owner rows in `docs/plan/qa/drop-box.md` are
run, including the NB5 recordings (OS-M5b-1). The record (E6) says which are open. **The P2-197 acceptance
(≥ 95 % on 50 recorded notch-bound drags, 0 accidental opens on 200 recorded normal drags) is an owner step and is
not claimed by Y7**, which runs on synthetic traces only.

---

## 8. Owner steps and open points

| ID | Item | Recommendation |
|---|---|---|
| OS-M5b-1 | **NB5 recordings** on the owner's Mac: 200 normal file drags (everyday targets: Finder windows, the Desktop, browser upload areas, Mail, the Dock, status items) and 50 drags aimed at the notch, with the Debug recorder (`qa/drop-box.md` §R). Then `make drag-replay TRACES=<folder>`; if it fails, `zivlet-traces tune <folder>` proposes constants and D1's `Config` changes in one commit | Record on the built-in display; add an external display set if one is at hand. Decide whether to commit the traces (timings and positions only) under `Fixtures/drag-traces/`; the default is to keep them local |
| OS-M5b-2 | **Hardware QA**: the B-, T-, C4- and S-rows of `qa/drop-box.md` (200 items out to Finder; promises from Mail, Photos and Safari; a tray drop in a full-screen Space; an external display's pill; AirDrop to a device; Quick Look from the panel; VoiceOver; the real Reduce Transparency, Increase Contrast and Reduce Motion settings; shake, opt-in) | After Y1–Y9 pass |
| OS-M5b-3 | **Screenshots of every box and tray state** (`make box-states`), as OWN-UI-1 asks before merge | Review with 19c open |
| OP-M5b-1 | The panel is dark in Light mode too (19c D-BL1) | Keep: it matches the island; one set of contrast numbers |
| OP-M5b-2 | Tray at rest: invisible sensor over the housing (D-BL10, D-M5b-17), or a visible tab under it while the box has items | Sensor. A tab is one surface value and one view away |
| OP-M5b-3 | If QA C4b shows a folder prompt when thumbnails of restored items are made after a relaunch: accept one prompt per protected folder, or show type icons for restored items until the person opens them | Decide after C4b; the code keeps the type icon path either way (D-M5b-14) |
| OP-M5b-4 | Settings rows and defaults (D-M5b-19): tray while dragging on, shake off, auto-clear off, drops to the most recent box | Keep; they follow OWN-APP-1…3 |
| OP-M5b-5 | Zip deferred to P2-111 (D-M5b-11) | Accept; P2-142 stays open for Zip |
| OS-M5b-4 | **Merge and push** of `m5b` | The owner decides after the record (E6) |

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Synthetic traces flatter the proximity rule; real drags to status items beside the housing open the tray | constants in one place; recordings decide (OS-M5b-1); the tray opens only after a 100 ms dwell and closes when the pointer leaves; a stray open shows a drop target, it moves nothing |
| A drop onto the island in a full-screen Space is not delivered (not prototyped) | QA T4 on hardware; the panel (menu, BOX slice) still works; shake (opt-in) still works |
| Restored items in protected folders raise a TCC prompt when their thumbnails are made | type icons first; nothing read until shown (D-M5b-14); QA C4b; OP-M5b-3 |
| File promises behave differently per source app | the port isolates them (D-M5b-5); QA rows for Mail, Photos, Safari; failures become per-item lines |
| Quick Look from a non-activating panel needs the panel key and in the responder chain | B8 makes the panel key on Space as a click does (§3.1 showed key without activation); QA B9 |
| The arbiter change (D-M5b-6) alters which client the HUD yields to | table tests for every pair of resting surfaces before and after (D8); the HUD's own tests stay green |
| 200-item drags out are slow or partial | the payload builds in 30 ms (§3.1); QA B5 on hardware |
| `UndoLog` schema 2 breaks existing undo files | decoding of schema-1 fixtures in C5's tests; a damaged file is logged and treated as empty, as today |
| The session ends mid-plan | every task is green and committed on `m5b`; E6 records where it stopped |

---

## 10. Gaps recorded up front

| ID | Gap | Next step |
|---|---|---|
| G-M5b-1 | Zip (P2-142) is not built: EngineArchive (P2-111) does not exist | Add the Zip button with P2-111 |
| G-M5b-2 | The P2-197 detection acceptance is not measured until the owner records real drags | OS-M5b-1 |
| G-M5b-3 | Not prototyped: a real drag into the panel or the island, a real drag out to Finder, a full-screen drop, Quick Look from the panel, AirDrop's sheet from the panel | QA rows B5, B9, T4, B12 |
| G-M5b-4 | C4: content reads after relaunch, a real USB volume, the real Finder pasteboard, and Zivlet's existing folder access were not checked | QA C4a–C4d |

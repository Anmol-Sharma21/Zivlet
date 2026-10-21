# Roadmap cluster: app features (Drop Box, Custom Wheels, History, `zivlet` CLI)

> Imported into the repository on 2026-10-21 from the roadmap drafts; approved by the owner the same day
> (see [00-decisions.md](00-decisions.md), 2026-10-21 section). The product name is Zivlet.
> Prototype folders named `<name>.XXXX/` are local prototypes and are not published.
> The "17-* files" below are now [17-feature-roadmap.md](17-feature-roadmap.md), [17-roadmap-challenge.md](17-roadmap-challenge.md),
> [01b-prd-additions.md](../plan/01b-prd-additions.md) and [05-task-list.md §9](../plan/05-task-list.md).

> [challenge] Adversarial review 2026-10-21 ([17-roadmap-challenge.md](17-roadmap-challenge.md)). The 17-* files are authoritative wherever they differ from this report. Corrections that apply here:
> - The menu-bar Recent list stays at **20** (PRD §6.6, FR-39), not 10.
> - The CLI subset is M, not S. swift-argument-parser is already budgeted (10 §9/§10), so its +0.83 MB is not new size.
> - The notch tray (owner pick, after this report) has no prototype here. Spike P2-197 gates it.

> **Update 2026-10-22 (owner, after M4).** The Drop Box with the notch tray moves to the front of the first public beta
> (0.5), and a new pick, the Notch HUD, shares the notch island with it. §2a describes both in our own words.
> - PRD §6.7 ("never copies") must change if the box keeps owned copies of promise/clipping content.

Date: 2026-10-21. Status: proposal for the owner. Scope: the four "app" picks from the owner's list
(00-decisions, 2026-10-21): the Drop Box shelf, custom wheels (slices, order, colours), history of recent jobs, and the
command-line tool. Transcription is designed separately. This file only reserves its places (a tool slice, a history
kind and a CLI verb).

Inputs read: design/00-decisions, 10-tech-strategy (§9 size, §10 licences, §12 roadmap), 12, 13, 14-app-platform
(§3.1 menu, §4.4 CLI); plan/01-prd (§5.5 wheel, §6.6 menu, §6.7 Float, §6.8 CLI, §6.9 backlog), 02-architecture
(§2, §4, §5.2, §7.7, §10), 03a §4.7 (undo), 03b §7 (Actions) and §8.1 (Settings), 05-task-list (P1-15, P1-44/45,
P2-55, P3-31, B4-15/16). I also read the current code: `ZivletWheelCore/SliceBuilder*.swift`,
`ZivletCore/Catalog/ToolTable.swift`, `ZivletRuntime/UndoLog.swift`, `UndoHistory.swift`,
`ZivletWheel/AccentPalette.swift`.

Principles applied: everything local and offline, no telemetry, no new network use. Bundle stays ≤ 70 MB: none of the
four features adds more than about 1 MB. Clean room: prior-art apps are described only by their general behaviour, in
our own words. No code, strings or assets come from the reference app, Open-Tangerine, Dropover or Yoink.

Evidence caveat: the prototypes ran on this Mac (macOS 27.0 build 26A428, arm64, Swift 6.4, Xcode at
`/Applications/Xcode.app`) while other agents were building. `uptime` showed a **load average of about 255**, so the
timings are upper bounds. Repeat runs varied by up to 10× (JSON read of 2,000 entries: 1,518 ms, then 161 ms).
Prototype folders are listed in §8.

---

## 1. Summary

| Feature | What the user gets | Main modules (02 §4) | New deps (licence, size) | Effort | Phase |
|---|---|---|---|---|---|
| Drop Box | One big floating box. Collect files from many places, then Share, AirDrop, Copy, Move to…, Copy to…, Zip or drag them all out at once. It grows out of the planned **Float** action. | `ZivletActions` (panel, views), new pure `ZivletShelfCore`, `ZivletUI` (coordinator for Zip/Convert-all) | None. AppKit, QuickLookThumbnailing, Foundation bookmarks: 0 MB | **L** (P2-55 was L; bulk actions add M) | **P2, first in beta 0.5** (owner, 2026-10-22), with the notch tray and the Notch HUD (§2a). Shake-to-open is opt-in in P2, on by default after trace QA. |
| Custom Wheels | Choose which slices show in each wheel and their order. Hide or show slices. Built-in presets. Accent colour per wheel and an optional colour per slice. Import and export. | New pure `ZivletPresets` (planned in 02 §5.2 for 1.x), `ZivletWheelCore` (cap and apply), `ZivletWheel` (colours), `ZivletUI` (Wheels pane) | None: 0 MB | **M + M** | **P2:** hide, order, per-mode accent, 12-slice cap rule. **P3:** per-slice colours, presets, import and export, pinned preset slices. Moved up from B4-16 (P4). |
| History | A recent-jobs window and menu with Reveal, Undo, Re-run, Remove and Clear. Retention setting and a "don't keep history" switch. | `ZivletRuntime` (`HistoryLog` grows out of `UndoLog`), `ZivletUI` (History window, menu) | None. JSON + Foundation: 0 MB (SwiftData rejected, §4.3) | **M** | **P1** already has Recent results (20 entries, 24 h undo). **P2:** History window, re-run, retention. |
| `zivlet` CLI | `zivlet convert/tool/formats/info/history/box/wheel`, `--json` output, NDJSON progress, fixed exit codes, Homebrew cask. | `zivlet-cli` (thin executable) + `ZivletCLIKit` (testable commands); shares `ZivletCore` Catalog, `ZivletRuntime`, `ZivletEngines` | swift-argument-parser 1.7.2 (Apache-2.0 with Runtime Library Exception, GPL-compatible): **+0.83 MB stripped**, measured | **M** (P3-31) + **S** early subset | **P2 (late):** `formats`, `info`, `convert` headless, also usable as a test harness. **P3:** `tool`, `wheel`, `history`, `box`, cask, completions. |

---

## 2. Drop Box (extends the Float action)

### 2.1 Relationship to what is already planned

- 03b §7 row 2 and PRD §6.7 already specify **Float**: a non-activating floating `NSPanel` on all Spaces, several
  shelves, edge docking (attach 28 pt, detach 48 pt, move after 8 pt), Quick Look thumbnails, drag-out, marquee and
  type-to-select (0.8 s reset). It keeps references, never copies, survives relaunch, and greys missing files with
  "Locate…". Task P2-55 (L).
- The owner asked for more than a parking spot. The box should take files from many places and then **act on all of
  them at once**: share, copy, move. So the Drop Box **is** the Float shelf with a bulk-action bar, totals, and a
  "temporary" lifecycle. There is one component, not two.
- Naming: the Actions slice stays one slot. I suggest the wheel label "BOX" with SF Symbol `tray.full` instead of
  "FLOAT". `ActionID.pinFloating` keeps its raw value so stored layouts still decode. **[OWNER]** label choice.

### 2.2 Prior art, in our own words (not installed here, not copied)

- One kind of shelf app pops up a small floating box when you shake the pointer during a drag. You drop files into
  it, add more from other windows, then drag the whole stack out at once or apply a quick action to it. You can keep
  several boxes.
- Another kind slides a narrow shelf in from a screen edge as soon as a drag starts. Items wait there until you drag
  them out. It keeps references to the files, and it keeps its own copy only of content that has no file behind it.
- What we take as goals: no click to open while dragging, take whole stacks in and out, act in bulk, and never move
  data anywhere by surprise. We do **not** take cloud upload, link sharing or clipboard-history features: they need
  network or go beyond scope.

### 2.3 User-facing behaviour

**Opening and adding**

| Way in | Behaviour | Permission |
|---|---|---|
| Actions wheel → BOX slice | Dropped items go into the box. `floatWheelBehavior` (03b §8.1) chooses between the most recent box (**proposed new default**, matching "one big box") and a new box. | none |
| Shake during a drag (opt-in in P2) | The trigger host already samples the pointer for every drag (ADR-09). A pure `ShakeDetector` looks for 4 horizontal reversals of at least 30 pt each within 0.6 s, then shows the box under the pointer so the drop lands in it. | none (same sampler) |
| Drop on a visible or docked box | The edge tab widens into a drop target while a drag hovers over it. | none |
| Menu bar → "Show Drop Box", optional global hotkey | Uses KeyboardShortcuts (MIT, already planned). No default binding. | none |
| CLI `zivlet box add FILES…` (P3) | Sent to the app over the P-CLI channel. | none |
| Services "Add to Drop Box" (P3, with P2-56) | Works from a Finder selection. | none |

**States** (pure `ShelfState`, rendered by `ZivletActions`)

| State | Look | Exits |
|---|---|---|
| Hidden | Nothing on screen. Box contents persist. | Any "way in" above |
| Docked | Thin tab on a screen edge showing the item count | Hover with a drag → Drop-target; click → Expanded |
| Collapsed | Small card: stacked thumbnails, "12 items · 84 MB" | Click → Expanded; drag the stack out |
| Expanded | Large grid or list, bulk-action bar, selection | Esc or ⌘W → Collapsed or Docked |
| Drop-target | Accent outline and "Add 3 items" during an external drag | Drop → Expanded (or the previous state) |
| Busy | Progress line while Move, Copy or Zip runs, with Cancel | Done → result toast ("Moved 12 items · Undo") |
| Attention | One or more items missing or in the Trash: amber count, "Locate…", "Remove missing" | Fixed or removed |
| Empty | Hint line "Drop files here to collect them" | Add → Expanded |

**Bulk actions** (on the selection, or all items when nothing is selected)

| Action | Implementation | Notes |
|---|---|---|
| Share… | `NSSharingServicePicker` anchored to the button. `sharingServices(forItems:)` is deprecated since macOS 13 (compiler warning seen in the prototype). | The prototype offered AirDrop, Mail and Messages for file URLs |
| AirDrop | Same code path as Actions row 1 (`NSSharingService(.sendViaAirDrop)`, `canPerform` first) | `canPerform` returned true for 3 files |
| Copy | Writes file URLs to the general pasteboard (Actions row 3) | Prototype: 200 URLs written and read back on a private pasteboard |
| Move to… / Copy to… | Reuses the Move action: "Move Here" panel, collisions → "name 2", cross-volume copy, verify and trash. Copy to… is the same without the trash step. One undo entry per batch (History, §4). | Box references follow the files after a Move (bookmarks resolve to the new path, §2.6) |
| Zip | Submits a `JobRequest` to Runtime (EngineArchive, P2). The Actions module must not import engines (R3), so this goes through the `ZivletUI` coordinator. | Output goes to the fallback folder or a chosen folder |
| Convert all… | Drag the stack out with ⇧ tapped: the wheel opens for the whole set (PRD §6.7 "Re-trigger"). | Mixed families use the k-of-n union rule |
| Remove from box | Only removes the reference | ⌫ |
| Move to Trash | Asks to confirm when more than 1 item is selected | ⌘⌫ |
| Clear box | Removes all references. Box-owned copies (below) go to the Trash. | Undoable for 10 s via the toast |

**"Temporary" lifecycle** (owner: "put the files for temporary purposes")

- References by default: the box never duplicates a file the user already has.
- Box-owned copies only for content with no stable file behind it: promise drags from Mail, Photos or a browser, and
  text or image clippings. These are stored under `~/Library/Application Support/Zivlet/Box/<box-id>/`. Settings
  shows the disk use and an "Empty box storage" button.
- Auto-clear options: off (default), "after items are dragged out or moved", "after 24 h". Owned copies go to the
  Trash, never `unlink`, so the user can recover them.

**Several boxes.** Allowed, as PRD §6.7 already says. The default is a single box, because the owner pictured "a big
box". ⌥ while dropping on BOX makes a new box. Each box has a name ("Box 2" or user-set) and its own frame and dock
edge. Cap: 8 boxes, so state stays understandable.

**Keyboard** (only when the box is key; it becomes key without activating the app, like the keyboard-mode wheel)

| Keys | Action |
|---|---|
| ⌘A, arrows, type-to-select | Select |
| Space | Quick Look |
| ⌘C | Copy files |
| ⌥⌘C | Copy paths (shell-quoted variant, as Copy Path) |
| ⇧⌘M / ⇧⌘C | Move to… / Copy to… |
| ⌘S | Share… |
| ⌫ / ⌘⌫ | Remove from box / Move to Trash |
| ⌘N | New box |
| ⌘1 / ⌘2 | Grid / list |
| Esc, ⌘W | Collapse or dock |

Accessibility: the box is an AX list with one AX row per item ("photo.heic, 2.1 MB, in Downloads"). Bulk-action
buttons are labelled. Reduce Motion replaces the slide-in with a fade.

### 2.4 Data model and persistence

- Pure `ZivletShelfCore` (Foundation only, rule R1): `Shelf { id, name, items: [ShelfItem], frame, dock, viewMode }`
  and `ShelfItem { id, bookmark: Data, lastKnownPath, displayName, byteCount, addedAt, ownership: .reference | .owned }`.
  Every edit returns a new value (`adding`, `removing`, `reordering`, `markingMissing`). This is where the logic and
  the tests live: de-duplication by file identity, totals, auto-clear planning, the shake detector.
- Store: `~/Library/Application Support/Zivlet/boxes.json`, schema-versioned, atomic write, mode 0600. Same pattern
  as the shipped `UndoStore`.
- Bookmarks: create with `.withoutImplicitSecurityScope` (smallest in the prototype, about 960 B) and resolve with
  `[.withoutUI, .withoutMounting, .withoutImplicitStartAccessing]`. Without the last flag, the unsandboxed prototype
  logged `sandbox_extension_consume failed: 1` once per resolve (200 lines for 200 items).
- Resolution is lazy: on show, not at launch, so launch stays fast. Stale bookmarks are refreshed and saved. A path
  that resolves under `/.Trash/` counts as **missing**, not present.

### 2.5 Engine and library choice

| Need | Choice | Licence and size |
|---|---|---|
| Panel, drag in and out, sharing | AppKit `NSPanel` (nonactivating), `NSDraggingSource`, `NSSharingServicePicker`, `NSSharingService` | system, 0 MB |
| Thumbnails and preview | `QLThumbnailGenerator`, `QLPreviewPanel` | system, 0 MB |
| Persistence | Foundation bookmarks + JSON | system, 0 MB |
| Zip all | EngineArchive (libarchive, already budgeted 1.8 MB) | BSD-2, already counted |
| Global hotkey | KeyboardShortcuts 3.1.0 (already planned) | MIT, already counted |

### 2.6 Evidence (prototypes on this Mac)

Folder `shelf.kibB/`. Build: `swiftc -O src/shelf.swift -o shelf && ./shelf $D/run`.

| Check | Result |
|---|---|
| Bookmark after the file is renamed **and** moved to another folder | Resolved to `…/other/a renamed.txt`, `stale: true` (so refresh and save) |
| Bookmark after the file is moved to the Trash | Resolved to `~/.Trash/b.txt`. Must be detected as missing (rule in §2.4). |
| Bookmark after the file is deleted | Error code 4 (file not found) → Attention state |
| Restore cost: resolve 200 bookmarks | 26–262 ms depending on options and load (`bm2.swift`). Lazy resolution is justified. |
| Bookmark size by option | default about 1,292 B, minimal about 1,316 B, `withoutImplicitSecurityScope` about 960 B. 200 items ≈ 356 KB as base64 JSON. |
| Log noise | 200 × `sandbox_extension_consume failed` without `.withoutImplicitStartAccessing`; none with it |
| Share services for 3 file URLs | `["AirDrop", "Mail", "Messages"]`. AirDrop `canPerform` = true. |
| Pasteboard, 200 file URLs (private board, not the user's clipboard) | write true, 200 read back |
| Copy-all / Move-all of 200 small files, same volume | 629 ms / 553 ms (under load). After Move-all, the box bookmark resolved to `…/dest2/f0.dat`. |
| Shake detector (`shake.swift`), 500 synthetic traces per case | Shakes at 3–6 Hz, ±40–120 pt: 500/500 detected. Straight, curved, hesitate-and-correct, 1 Hz wiggle, 8 Hz ±10 pt tremor: **0/500 false positives**. Synthetic data only: it needs real recorded traces (the repo has none yet, so add shake and non-shake drags to the P0-22 trace fixtures). |

### 2.7 Risks

| Risk | Mitigation |
|---|---|
| Shake triggers by accident during normal drags | Opt-in in P2. Thresholds come from recorded traces. A 300 ms cooldown after the wheel closes. |
| The box covers drop targets (Dock, other apps) | Click-through outside the drawn shape (already in 03b). Docked tab by default. Edge hysteresis. |
| Promise drags fill the disk with owned copies | Disk-use line, auto-clear options, cap warning at 2 GB **[OWNER]** value |
| A file inside the box changes on disk | The box shows live metadata. It never caches content. |
| Cross-volume Move-all partly fails | Reuses Move's verify-then-trash path. Per-item failure list. Undo restores the items that moved. |
| Interplay with the wheel trigger | Drags that start in our own windows are allowed (14 §1 table), so a stack dragged out of the box can open the wheel. Covered by trigger tests. |

**Dependencies:** P1-44/45 (Actions), P1-15 (undo), EngineArchive (P2) for Zip, the P2-56 Services entry, P-CLI for
`zivlet box`. **Effort:** L in total (P2-55 L, plus about M for bulk actions, ownership and auto-clear). **Phase:** P2, first in beta 0.5 (2026-10-22, §2a).

---

## 2a. Notch island: shared panel, Notch HUD, notch tray

Added 2026-10-22, after M4. The owner moved the notch Drop Box to the front of the first public beta and picked a new
feature, the **Notch HUD** ([00-decisions.md](00-decisions.md) OWN-PLAN-3 and OWN-HUD-1). This section is our own
design, written in our own words. No prototype exists yet: spike **P2-197** comes first and gates every row here.
Where a value below is a default, the assistant proposed it and the owner may change it.

### 2a.1 Order of work (first beta)

P2-197 notch spike → P2-115 NotchIsland core + P2-116 Notch HUD → P2-141 shelf core → P2-55 Drop Box panel (replaces
Float) → P2-142 bulk actions → P2-143 notch tray → then OCR, lock/unlock and the PDF basics. The choosable picker
style (Wheel or Bar) and place (at the cursor or at the notch) stays in the last phase and reuses the same panel.

### 2a.2 Prior art, in our own words

Several notch utilities treat the dark strip around the camera housing as a small live surface: a compact shape that
shows an icon or a ring, grows when the pointer comes near, and shrinks back on its own. Media and timer apps use it
for a glanceable status with a couple of controls. What we take as goals: glanceable progress where the eye already
goes, more detail only on hover, and nothing that steals focus. We do not take widgets, media controls or calendar
features: they are out of scope. No code, strings or assets come from any of these apps.

### 2a.3 NotchIsland: the shared panel (P2-115)

| Part | Behaviour |
|---|---|
| Window | A non-activating, borderless panel at a level above the menu bar, on all Spaces, including full-screen Spaces (P2-197 proves this on 26.x). It takes no focus when it appears; like today's HUD card, it becomes key only after a click into it (D-M4-16) |
| Geometry | The notch rectangle comes from `NSScreen.safeAreaInsets.top` and the gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. A pure `NotchGeometry` turns those into the collapsed and expanded frames, so it is tested in `swift test` with recorded screen values (14″ and 16″ notches, no notch, scaled modes) |
| Shapes | **Collapsed:** a strip just wider than the notch, the same height, with content in the two "ears" beside the camera. **Expanded:** grows down and out from the notch to a card about the size of today's HUD card (360 × 108 pt) |
| Displays without a notch | External displays, a closed lid, or a Mac without a notch: the island becomes a **top-centre pill** under the menu bar on the display where the drop happened (the drop point's screen, as `HUDLayout.screen(for:)` picks it today) |
| Hover | A tracking area on our own panel: no Accessibility or Input Monitoring. Hover expands after a short intent delay and holds the island open; leaving restarts the collapse timer |
| Click-through | Only the drawn shape takes clicks; the rest of the panel passes them through, so menu-bar items beside the notch keep working. The expanded card never covers menu-bar items beyond its own width |
| Motion | The collapsed ↔ expanded change springs out of the notch; with Reduce Motion it is a cross-fade only |
| Accessibility | One AX group that reads the same text as the current HUD card; buttons keep their labels; Increase Contrast uses the solid style |
| Users | The Notch HUD (P2-116), the notch tray (P2-143) and, in the last phase, the picker at the notch. One panel per display; the users share it through a small arbiter so a tray and a HUD never fight over the island (the tray wins during a drag, the HUD returns after) |

Module placement (proposed, settled in P2-197): a new AppKit module **`ZivletNotch`** holds the panel and the pure
geometry and state, below both `ZivletUI` (Notch HUD) and `ZivletActions` (tray), so neither has to import the other.
Size 0 MB: system frameworks and our own code.

### 2a.4 Notch HUD (P2-116)

The Notch HUD shows job progress, results and action toasts on the island instead of in the HUD card near the drop.
It re-hosts the content the HUD already has in `ZivletUI` (`HUDCopy`, `ResultCardModel` with its buttons and timings,
the action HUD content, `FileDragSource` for drag-out, `ThumbnailLoader`). Only the container and the collapsed and
expanded layouts are new, so the existing copy, timing and undo tests keep applying.

| State | Collapsed island | Expanded on hover |
|---|---|---|
| Working | The file's icon in one ear, a progress ring in the other (indeterminate when the fraction is unknown) | Today's working line: name, percent, time left, stage; Cancel |
| Done | Icon with a check mark | "Saved photo.jpg"-style line, sizes before → after, **Open**, **Show in Finder**, **Undo**; drag the result out of the card |
| Failed | Icon with a warning mark | The failure card's reason, **Retry**, Show Details when there are details, Close |
| Action toast | A short label in the ear: "Copied", "Moved" | "Moved 3 items" with **Undo**, as the action HUD's toast |
| Several jobs | "3 jobs" with a combined ring | A list: one row per job with its own ring or result and its own buttons |
| Waiting for input | Icon with a dot | The card that asks (for example a model download offer in Phase 3); it stays until answered |

Timing: the island collapses and leaves after the same linger times as today's HUD (success card 4 s; action toast
1.5 s, or 4 s when it offers Undo). While hovered it stays, and leaving restarts the full linger. Failures and cards
that ask stay until closed, as today.

Settings › General (defaults proposed by the assistant): "Show progress and results: **At the notch** | Bottom-right
corner". The default is "At the notch" on Macs with a built-in notch and the current HUD placement elsewhere. With "At
the notch" chosen, a drop on a display without a notch uses the top-centre pill on that display.

### 2a.5 Notch tray (P2-143)

The tray is the Drop Box's primary home (OWN-APP-2) and uses the same island. During a file drag, the pure
`NotchProximity` detector (fed by the existing permission-free drag sampler) expands the island into a drop target;
dropping stashes the items in the current box. Hover or click reopens it later as a compact box view, with the full
Drop Box panel (§2.3) one click away. When the wheel and the tray are both targets, the wheel wins. The 05 row P2-143
holds the acceptance.

### 2a.6 Open points and risks

| Item | Note |
|---|---|
| **OWN-HUD-2** (open) | The owner described today's HUD as "bottom-right". The current card opens below and to the right of the **drop point**, clamped 12 pt inside the screen (`HUDLayout`, 03a §4.5); it is not pinned to the screen's bottom-right corner. The second choice should say what it does. Recommendation: keep today's placement and label it "Near the drop"; a fixed corner is a small extra if the owner prefers it |
| Full screen and Spaces | Panels above the menu bar in full-screen Spaces are the main unknown; P2-197 measures it on 26.x. Fallback: the pill, then today's HUD card |
| Menu bar hidden or auto-hidden | The island must not reveal or block the menu bar; it shows only while a job or toast is live, or on hover |
| Several displays, lid closed | The drop's display decides; a closed lid means no notch, so the pill |
| Screen sharing | The island shows file names at the top centre of the shared screen, as the HUD card does today near the drop; no new exposure, but worth a line in the privacy notes |
| Apple changes | Notch metrics come only from public `NSScreen` APIs; no private calls, no hard-coded sizes beyond tested fallbacks |

**Dependencies:** P2-197 (spike), the `ZivletUI` HUD (M4), `ZivletSettings` (one new key), the drag sampler (tray).
**Effort:** P2-115 M, P2-116 M (ESTIMATE). **Size:** 0 MB. **FR:** FR-150 (reserved for the Notch HUD), FR-133 (tray).

---

## 3. Custom Wheels

### 3.1 Why now: the 12-slice cap will bite once the owner's tools land

- The PRD (§5.5) caps the wheel at 12 petals with no paging. In the code, `SliceBuilder` enforces `maxSlots` **only for
  mixed-family conversions** (`SliceBuilder+Convert.swift:33`). The tool lists and same-family conversions are passed
  through uncapped.
- Today the largest lists are 9 (PDF conversions, video tools). The owner's picks add to the PDF tool wheel: Lock,
  Unlock, Sign, Remove blank pages, Resize pages, Make searchable, and Copy text (OCR). That gives
  `shrink, stripMetadata, split, arrange, qrScan` + 7 = **12** for a single PDF, before any later tool. Video gains
  Remove silence and Transcribe (reserved), which gives 11. Image gains Copy text, Remove background and Resize, which
  gives 10.
- So two rules are needed **before** those tools ship, whatever happens to customisation:
  1. **Catalog rule:** each applicability row marks its tools `defaultVisible` or `extra`. The builder shows the
     visible ones in catalog order, capped at 12. Extras are reachable through the custom-wheel editor, App Intents and
     the CLI. A test fails if any default list exceeds 12.
  2. **Custom wheels** let each user choose which 12.
- **[OWNER]** Optional "More…" 12th slice that opens a searchable list panel at the wheel. It breaks "no paging" in
  spirit, so it is off by default and decided after the usability test.

### 3.2 User-facing behaviour

- **Settings › Wheels pane** (new, `ZivletUI`). A mode picker (Convert, Tools, Actions) and a scope picker (Any file,
  Images, Audio, Video, PDF, Documents, … or one specific format). A list of the slices the catalog offers for that
  scope: drag to reorder, checkbox to show or hide, a "12 of 12 shown" counter, and a live wheel preview beside it
  using the real `WheelView`.
- **Scope resolution:** a format-specific layout wins over a family layout, which wins over the built-in default.
  Actions has one global layout.
- **Rules the editor enforces** (02 §10: "slots still come from Catalog; no free-form commands"):
  - Only catalog slices appear. There are no user scripts or commands (ADR-12).
  - At most 12 shown. Checking a 13th asks which one to hide.
  - At least 1 shown per mode.
  - At drag time the layout only **filters and orders** what the catalog offers for the current selection.
    Single-file tools disappear for multi-file drags and capability-hidden routes stay hidden (03a §3.5).
  - New tools from an update appear at the end of a custom layout, shown if room remains, otherwise hidden. A
    "New: 2 tools" badge appears in the pane.
- **Presets** (built-in, read-only, duplicable): Default; Minimal (6 most-used per mode); Creator (Instagram 9:16,
  1:1, 4:5 and fit-to-size WhatsApp, Gmail and Discord as pinned preset slices, from the presets cluster); Office and
  PDF (Lock, Unlock, Sign, Merge, Compress, Make searchable first). Users can save their own.
- **Colours:**
  - An accent per wheel (Convert, Tools, Actions). This also helps people tell the modes apart. The default is the
    system accent for all three, as today (D-M2-4).
  - An optional colour per slice from a 12-swatch palette, or a custom colour picker in P3.
  - Labels pick white or black automatically (`AccentPalette.labelOnAccent`, already shipped).
  - In light mode, if a fill falls below 3:1 against the background (WCAG 1.4.11 non-text), the petal gets the
    palette's dark-stop outline. A swatch that fails is marked "low contrast" in the picker.
  - Colour never carries meaning alone: label and symbol stay (WCAG 1.4.1).
  - Glass theme: contrast over arbitrary desktops cannot be guaranteed, so the guarantees apply to the Solid theme and
    to the existing idle scrim (03a §2.2).
- **Import and export:** a `.zivletwheel` file (UTF-8 JSON, our exported UTType conforming to `public.json`).
  Export via the Share menu or Save. Import via double-click or a drop on the pane. Import shows a diff ("adds 2
  layouts, 1 unknown slice ignored") and applies only after confirmation. Size cap 256 KB. Names are cut to 64
  characters, unknown slice ids and bad colours are reported (never silently dropped), and duplicates are removed.
- **Keyboard and accessibility:** list reorder with ⌥⌘↑/↓. VoiceOver reads "WEBP, shown, 3 of 12, colour blue". The
  keyboard-mode wheel's 1–9 shortcuts follow the custom order.

### 3.3 Model and placement

```swift
// ZivletPresets (pure, Foundation only; depends on ZivletCore + ZivletWheelCore)
public struct WheelLayout: Sendable, Codable, Equatable {
    public let mode: WheelMode
    public let scope: LayoutScope            // .any | .family(FormatFamily) | .format(FormatID)
    public let order: [SliceID]              // "tools.pdfSign"; ids already stable per mode (SliceBuilder)
    public let hidden: Set<SliceID>
    public let accent: RGBHex?               // nil → system accent
    public let sliceColours: [SliceID: RGBHex]
}
public struct LayoutLibrary: Sendable, Codable { public let schema: Int; public let active: PresetID; public let presets: [WheelPreset] }
public enum LayoutApplier { public static func apply(_ l: WheelLayout?, offered: [WheelSlice], cap: Int) -> [WheelSlice] }
public enum LayoutImporter { public static func validate(_ data: Data, catalog: SliceUniverse) throws(LayoutImportError) -> (LayoutLibrary, [LayoutIssue]) }
```

- `SliceBuilder.content(...)` gains an optional `WheelLayout` input. Stored layouts live in a new `SettingsStore`
  group, "Wheels" (UserDefaults, versioned Codable, 03b §8.1). One layout is about 266 B of JSON (measured).
- Move `RGB`, its luminance and its contrast maths from `ZivletWheel/AccentPalette.swift` (an AppKit module) into
  `ZivletWheelCore`, so the importer can validate contrast in `swift test` without AppKit (rule R1).
- `SliceTarget` gains `.preset(PresetID)` when the presets cluster lands. The layout treats it like any other slice.

### 3.4 Evidence (prototype on this Mac)

Folder `wheels.Lbzf/`. Build: `swiftc -O src/wheels.swift -o wheels && ./wheels`.

Contrast of a 12-swatch candidate palette (WCAG 2 ratios). Background stand-ins: light #ECECEC, dark #1E1E1E.

| Swatch | Auto label | Label:fill | Fill:light bg | Fill:dark bg |
|---|---|---|---|---|
| Orange #F28C28 | black | 8.56 | **2.07** | 6.79 |
| Red #E5484D | black | 5.37 | 3.31 | 4.26 |
| Pink #D6409F | black | 5.09 | 3.49 | 4.04 |
| Purple #8E4EC6 | white | 5.18 | 4.38 | 3.22 |
| Indigo #3E63DD | white | 5.21 | 4.40 | 3.20 |
| Blue #0090FF | black | 6.43 | **2.76** | 5.10 |
| Teal #12A594 | black | 6.84 | **2.60** | 5.42 |
| Green #30A46C | black | 6.65 | **2.67** | 5.28 |
| Lime #BDEE63 | black | 15.57 | **1.14** | 12.35 |
| Yellow #FFE629 | black | 16.60 | **1.07** | 13.17 |
| Brown #AD7F58 | black | 5.95 | **2.98** | 4.72 |
| Graphite #8B8D98 | black | 6.36 | **2.79** | 5.04 |

- Label text always passes: the minimum is 5.09:1, above the 4.5 target.
- Only Red, Pink, Purple and Indigo reach 3:1 against **both** backgrounds. Eight swatches fail against the light
  background, which justifies the automatic outline rule.
- Adjacent swatches in wheel order: worst ΔE76 is 22.1 with normal vision and **12.6 with simulated deuteranopia**
  (Machado 2009 matrix; Indigo next to Blue). They stay distinguishable but close, so colour must not be the only cue.
- Layout validation: input had order `[pdfSign, pdfLock, shrink, ghost, pdfLock]`, hidden `[qrScan, stripMetadata]`
  and an accent per slice. The validator reported `unknownSlice("tools.ghost")` and `duplicate("tools.pdfLock")`.
  Applied to 13 offered PDF tools, the result was 11 shown in the user's order, with new tools appended and no
  overflow. Without a layout, 13 offered tools gave **1 overflow** (`pdfRotate`), which shows the cap problem from
  §3.1.
- For a 2-file PDF selection the same layout correctly dropped single-file Sign and Arrange and appended Merge.
- Hostile import (a 5 MB name and 10,000 unknown ids) was cleaned in 5.2 ms. The name was cut to 64 characters and the
  order emptied. Two defects to fix in the real code: the issue list must be **capped** (10,000 issues were returned),
  and the bad-hex slice colour was dropped **without** an issue.

### 3.5 Risks

| Risk | Mitigation |
|---|---|
| Custom order breaks muscle memory taught by onboarding | Onboarding uses the active layout. "Reset to Default" per mode. |
| Catalog updates rename or retire slice ids | Slice ids are stable raw values (already a rule). A migration table maps retired ids. Unknown ids are reported. |
| Imported files as an attack surface | Size cap, schema check, no code, ids checked against the catalog, confirm-before-apply diff |
| Per-slice colours become visual noise | Off by default. Palette limited to 12 swatches in P2. Custom picker in P3. |
| Glass tint lowers contrast | Solid theme automatically under Increase Contrast (already planned). Outline rule. |

**Dependencies:** the SettingsStore group (P1-46), keyboard-mode wheel (P3-34) for 1–9 order, the presets cluster
for `.preset` slices, and the tool catalog growth (PDF and image clusters). **Effort:** P2 M (model, cap rule,
hide/order, per-mode accent, Settings list); P3 M (per-slice colour, presets, import and export, preview polish).
**Phase:** P2 + P3. The catalog cap rule (§3.1, part 1) should ship with the first PDF tool beyond today's set,
whatever its phase.

---

## 4. History

### 4.1 What exists

- PRD FR-39 and §6.6 give "Recent results (last 20): Reveal, Undo" in the menu. 03a §4.7 gives the undo rule: an
  output goes to the Trash only if its identifier, size and mtime still match.
- The code ships `UndoLog` (20 entries, **24 h lifetime**, newest first, immutable) and `UndoHistory` (an actor; JSON
  at `~/Library/Application Support/Zivlet/undo.json`; a damaged file is logged and treated as empty).
- P1-15 in the task list says "history of 50", but the code and 03a say 20. Reconcile when History lands (below).

### 4.2 User-facing behaviour

| Surface | Content |
|---|---|
| Menu bar "Recent" (P1, exists) | The last 10 rows [challenge: PRD §6.6 says 20; keep 20]: icon, "photo.heic → WEBP", relative time. Click reveals the output. Undo is enabled while undoable. "Show All History…" opens the window. |
| History window (P2) | Table: Time, Operation ("Converted to WEBP", "Compressed", "Moved 12 items", "Locked PDF"), Items, Result (sizes before → after, or failure reason), Status. Search field (file name or operation). Filter by kind and by "failed only". |
| Row actions | **Reveal** (outputs or moved items). **Undo** (see the rules below). **Re-run** (same operation and options on the same inputs, with new output names by the collision rule). **Re-run with…** (opens the wheel for those inputs in keyboard mode). **Copy details**. **Remove from history**. |
| Window actions | **Clear History…** (confirm), and "Clear failed". |
| Drag | Dragging a row drags its output files (Finder, Mail, Drop Box). |
| Settings › General › History | Keep history: Off / 7 days / **30 days** (default) / 90 days. Max 500 entries. "Clear now". The undo window stays 24 h whatever the setting (safety: Undo only trashes files that still match). |

- **Undo rules:** convert and tool batches trash matching outputs, as today. Move batches move items back (03a §4.7).
  Bulk Move from the Drop Box is one entry. Lock and Unlock (other clusters) produce new files, so Undo trashes them;
  originals are never modified. Rows older than 24 h show Undo disabled, with the tooltip "Undo is available for 24
  hours".
- **Re-run:** the entry stores the Codable `JobRequest`s (already Codable in `ZivletCore/Jobs/JobRequest.swift`).
  Re-run rebuilds each through the throwing initialiser, so it re-checks the catalog pair and the destination
  safety. Missing inputs are listed ("2 of 5 files are no longer there"), never silently skipped. Secrets are never
  stored: password-taking tools (Lock, Unlock, Sign) keep only `passwordProvided: true`, and Re-run asks for the
  password again.
- Transcription (reserved): history kind `transcribe` with the language and model id. Its design is owned by the
  transcription work.

### 4.3 Storage decision: JSON (actor + atomic file), not SwiftData

Prototype folder `history.j3qC/`. Build: `swiftc -O src/json.swift` and `swiftc -O -parse-as-library src/sd.swift`.

| Measure | JSON (`[Entry]`, 3 inputs + 3 outputs each, ISO dates) | SwiftData (`@Model`, fewer fields) |
|---|---|---|
| 2,000 entries on disk | 1,832 KB, one file | 3,124 KB store + 4,840 KB WAL + 32 KB shm |
| Write all / insert + save 2,000 | 39–736 ms (load-dependent) | 680 ms |
| Read all / fetch latest 50 | 161–1,518 ms for all 2,000 (load-dependent); 12 ms for 100 | 16 ms (fetch 50); 127 ms container open |
| Prune > 30 days | 0.75–2 ms in memory | 65 ms |
| **Deleted paths left in the file** | None. Atomic replace writes a new file. | **Yes.** After a SwiftData delete of entries older than 30 days, `grep -c IMG_2999 history.store` = 2. `pragma wal_checkpoint` left 2. Only `vacuum` removed them (0), on a copy of the store. |
| Bundle cost | 0 | 0 (system framework, `otool -L` shows SwiftData) |

Decision: **JSON.**

- At the planned scale (≤ 500 entries ≈ 450 KB) it is simple and fast.
- It matches the shipped `UndoStore` pattern and keeps `ZivletRuntime` pure-testable (no model container).
- "Clear history" really removes the paths from the file. With SQLite, deleted rows linger in free pages and the WAL
  until a vacuum, which matters because file paths are personal data.
- Revisit SwiftData only if history grows past roughly 5,000 entries or needs full-text search.

Implementation: evolve `UndoLog` into `HistoryLog`:

- Each `HistoryEntry` has `kind`, `requests`, `outputs`/`moves`, `status`, `error`, `sizes`, `date`, `duration`.
  `isUndoable(now:)` is computed from the 24 h window plus the stamps.
- One file, `history.json`, written by an actor with atomic writes and mode 0600.
- A one-time migration reads `undo.json`, then moves it to the Trash.
- The 500-entry and retention caps are applied on every write.

### 4.4 Privacy and retention

- The history stays on this Mac in `~/Library/Application Support/Zivlet/`, mode 0600 (verified: `perms: 600`). It
  is never sent anywhere (no telemetry, decision 00).
- It contains file names and paths only. No file contents, thumbnails or passwords.
- "Keep history: Off" still keeps the 24 h undo data. A footnote says so. Undo data is the minimum needed to undo.
  **[OWNER]** confirm that Off may still keep 24 h undo data.
- Time Machine: the file is excluded with `isExcludedFromBackup = true`, so old paths don't persist in backups.
  **[OWNER]** confirm. The default proposed is excluded.
- "Copy diagnostics" (Settings › Advanced) leaves out history unless the user ticks "include recent history (paths
  shown)".

### 4.5 Risks

| Risk | Mitigation |
|---|---|
| Re-run on changed inputs produces surprising output | Re-run shows "N files changed since last run" before starting. Outputs never overwrite (collision rule). |
| A history file damaged by a crash | Atomic write. A damaged file is renamed `history.damaged.json`, the log starts empty, and the event is logged (existing pattern). |
| Paths are sensitive (client names) | Retention default 30 days, Off switch, Clear, backup exclusion, no diagnostics by default |
| Undo of a Drop Box Move after the user re-moves files | The stamp check skips changed items and lists them, as in the existing `UndoPlanner` |

**Dependencies:** P1-15 (UndoLog, done), the P1 menu, the Move action, other clusters' tools for kinds. **Effort:** M.
**Phase:** P2 (window, re-run, retention). The P1 menu stays as is.

---

## 5. `zivlet` command-line tool

### 5.1 Placement and sharing

- Targets: an executable `zivlet-cli` (product `zivlet`) and a library `ZivletCLIKit` that holds the commands, so
  `swift test` covers parsing and the JSON shapes.
- It links `ZivletCore` (the Catalog: one source of truth, P4), `ZivletRuntime` (scheduler, Publisher, naming,
  history) and the dynamic `ZivletEngines` product from P2 (ADR-10, spike P-PKG). There is no duplicate engine code,
  and the app and the CLI share one copy of the engines in the bundle.
- It runs engines in-process and headless (14 §4.4). For WebKit-rendered document routes, Drop Box and history writes,
  it talks to the running app over the P-CLI channel (02 §2.2: Unix socket with an audit-token signature check, or an
  `SMAppService.agent`). If the app isn't running, those commands say so and exit 3 (routes) or 1 (box).
- Helpers are found from the binary's real path. The prototype showed that `CommandLine.arguments[0]` is **wrong**
  when the tool is invoked via `PATH`: it printed `/Helpers`. `Bundle.main.executableURL!.resolvingSymlinksInPath()`
  gave the correct `…/fake.app/Contents/Helpers` through a symlink in `bin/`.

### 5.2 Commands

```
zivlet convert FILES… --to webp [--quality fast|balanced|high|0-100] [--out-dir DIR] [--json] [--progress ndjson]
zivlet tool <tool-id> FILES… [tool options] [--json]        # ids from the Catalog: shrink, strip-metadata, pdf-lock …
zivlet formats [--from heic] [--json]                        # Catalog dump; also feeds docs and tests
zivlet tools [--for pdf] [--json]                            # which tools apply, cardinality, options schema
zivlet info FILE [--json]                                    # probe: type, size, dimensions, duration, pages, streams
zivlet history [--limit 20] [--json] | history undo <id> | history clear   # P3, via the app's HistoryLog file
zivlet box add|list|clear [FILES…] [--json]                  # P3, needs the app
zivlet wheel FILES…                                          # opens the wheel in keyboard mode (app)
zivlet transcribe …                                          # reserved verb; design owned by the transcription work
```

- **JSON contract:** one envelope `{ "schema": 1, "ok": bool, "data": … }` with sorted keys and no escaped slashes.
  Per-item results are `{input, output?, bytes?, error?}`. Error text is the same `JobError` user copy as the app.
  `--progress ndjson` streams `{"event":"progress","input":…,"fraction":0.42}` lines to stderr. Stdout stays one JSON
  document.
- **Exit codes** (14 §4.4): 0 ok, 1 some items failed, 2 usage, 3 unsupported pair or needs-app, 130 cancelled.
  - ArgumentParser's default for usage errors is **64**, as the prototype showed, so a custom `main()` maps
    validation failures to 2. Verified: usage → 2, `--help` → 0.
  - SIGINT: a `DispatchSource` signal handler cancels the scheduler, kills helper process groups (same teardown as
    the app), and exits 130.
- **Passwords** (Lock and Unlock from the PDF and file-protection clusters): never accepted as a plain argument.
  `ps` shows every argument to other processes (verified: `ps -o args=` printed `… --password hunter2`). Options are
  `--password-stdin` or an interactive no-echo prompt (`readpassphrase`).
- **Offline:** the CLI makes no network calls. Optional model downloads (transcription, Ask) happen only from the app,
  after the user agrees.

### 5.3 Install and distribution

- Homebrew cask (owner's choice of tap or the main repo):
  `binary "#{appdir}/Zivlet.app/Contents/Helpers/zivlet"`, `zsh_completion` / `bash_completion` /
  `fish_completion` stanzas pointing at completion files generated at build time
  (`zivlet --generate-completion-script zsh` produced a 135-line script in the prototype), and
  `livecheck strategy :sparkle` (14 §3.5). `brew` 7.0.7 is present on this Mac. The cask itself is unverified here (no
  network cask fetch was attempted).
- Settings › Advanced › "Install command-line tool": creates a symlink in `~/.local/bin` (no admin), or in
  `/usr/local/bin` after an admin prompt (14 §4.4). "Uninstall" removes only our symlink.
- Signing: a hardened-runtime helper with no entitlements, signed inside-out with the app (10 §11.2). Gatekeeper
  accepts it because the app is notarized.

### 5.4 Evidence (prototype on this Mac)

Folder `cli.BdWq/`. swift-argument-parser 1.7.2 was cloned into `sap/`; the prototype package is `proto/`.
Build: `swift build -c release` (87–97 s under load).

| Check | Result |
|---|---|
| Binary size | 1,727,544 B unstripped; **878,800 B** `strip -x`. A Foundation + ImageIO baseline is 51,064 B, so ArgumentParser and the commands add about **0.83 MB**. |
| Linked libraries | System only (Foundation, ImageIO, libswiftCore …). Nothing to bundle. |
| `convert a.heic b.heic --to jpg --out-dir out --json` (6016×6016 HEIC; b is junk) | a → 8.8 MB JPEG; b → `"error": "Zivlet can't read this file."`; `"ok": false`; **exit 1**; 2.0 s wall under load |
| `convert --to xyz` | stderr message, **exit 3** |
| `convert` with no files | Usage text; default **exit 64**; after the custom `main()`, **exit 2** |
| `info a.heic --json` | `{bytes 26284797, type public.heic, width 6016, height 6016}` |
| `formats --from heic --json` | Envelope with targets `[jpg, png, tiff]` |
| Helper lookup via `PATH` symlink | Wrong with `argv[0]` (`/Helpers`), right with `Bundle.main.executableURL` |
| Completions | `--generate-completion-script zsh` → 135 lines |
| Password in argv | Visible in `ps -o args=` (so `--password-stdin` is the rule) |

### 5.5 Risks

| Risk | Mitigation |
|---|---|
| CLI and app run jobs at the same time on the same files | Both use `NameReserver` semantics on disk (exclusive create and rename, ADR-08), so no partial or overwritten outputs |
| Linking `ZivletEngines` from a helper outside `Frameworks/` | `@executable_path/../Frameworks` rpath. Covered by spike P-PKG and the signature gate. |
| JSON schema drift breaks scripts | `schema` field; golden JSON tests in `ZivletCLIKit`; additive changes only within a major version |
| Catalog and CLI tool names diverge | Tool ids are generated from `ToolID` raw values (kebab-cased) in one table, tested against the Catalog |
| Password tools in scripts | Stdin only. Never logged. Never stored in history. |

**Dependencies:** P2-01 (worker; the dynamic `ZivletEngines` product arrives with it, ADR-10), spike P-PKG, P-CLI (P3), the Catalog, and the Runtime Publisher.
**Effort:** S (P2 subset) + M (P3-31). **Phase:** P2 late for `formats`, `info` and `convert` (it doubles as the
integration and benchmark harness for the nightly matrix). P3 for the rest, the cask and completions.

---

## 6. Module map and proposed task rows

| Proposed ID | Title | Module(s) | Deps | Size | Phase |
|---|---|---|---|---|---|
| P2-115 | NotchIsland core (§2a.3): panel, `NotchGeometry`, hover, pill fallback, Reduce Motion fade, arbiter | ZivletNotch (new, proposed) | P2-197 | M | P2, 0.5 (first) |
| P2-116 | Notch HUD (§2a.4): HUD content on the island, states, linger rules, Settings › General choice | ZivletUI, ZivletNotch, ZivletSettings | P2-115 | M | P2, 0.5 (first) |
| P2-55a | Drop Box core: `ZivletShelfCore` model, JSON store, bookmark rules, Trash detection | ZivletShelfCore (new, pure) | P1-44 | M | P2 |
| P2-55b | Drop Box panel: states, dock, grid and list, QL, keyboard, AX | ZivletActions | P2-55a | L (was P2-55) | P2 |
| P2-55c | Bulk actions: Share picker, AirDrop, Copy, Move to / Copy to with undo, Zip via coordinator, owned copies, auto-clear | ZivletActions, ZivletUI | P2-55b, P1-45, EngineArchive | M | P2 |
| P2-55d | Shake-to-open (opt-in) with recorded traces | ZivletTrigger (pure detector), TriggerHost | P0-22 traces | S | P2 |
| P2-70 | Catalog cap rule (`defaultVisible`, ≤ 12 per list, test) | ZivletCore, ZivletWheelCore | — | S | with the first new PDF or image tool |
| P2-71 | Custom wheels v1: `ZivletPresets`, layout apply, hide and order, per-mode accent, Settings › Wheels, RGB maths moved to WheelCore | ZivletPresets (new), WheelCore, Wheel, UI | P1-46, P2-70 | M | P2 |
| P3-50 | Custom wheels v2: per-slice colours and contrast outline, built-in presets, `.zivletwheel` import and export, `.preset` slices | ZivletPresets, UI | P2-71, presets cluster | M | P3 |
| P2-72 | History v1: `HistoryLog` (evolves UndoLog), migration, retention, window, Reveal, Undo, Re-run, Clear, backup exclusion | ZivletRuntime, ZivletUI | P1-15 | M | P2 |
| P2-73 | CLI subset: `ZivletCLIKit` + `zivlet formats/info/convert`, JSON envelope, exit-code mapping, SIGINT 130 | zivlet-cli | P2-01, P-PKG | S | P2 (late) |
| P3-31 | CLI complete: `tool`, `tools`, `wheel`, `history`, `box`, P-CLI channel, cask, completions, Install CLI button | zivlet-cli, App | P2-73, P-CLI | M | P3 |

The changes to 02 §4.1 that this implies:

- Add `ZivletShelfCore` (domain, pure, P2).
- Add `ZivletNotch` (shell, AppKit panel + pure geometry, P2; proposed in §2a.3).
- Bring `ZivletPresets` forward from 1.x to P2.
- Add `ZivletCLIKit` (front-end library, P2).
- Change `zivlet-cli` from "P3" to "P2 subset, P3 complete".
- 05 backlog B4-16 (customisable wheels) moves to P2-71 and P3-50.

---

## 7. Owner decisions

1. **Label for the BOX slice** (replaces "FLOAT"), and whether the default is "add to the most recent box" (proposed)
   or "new box" (current 03b default).
2. **Shake-to-open:** opt-in in P2, then on by default after trace QA? (proposed yes)
3. **Box storage cap warning** for owned copies (proposed 2 GB) and the auto-clear default (proposed off).
4. **"More…" 12th slice** for overflow: test it in usability, off by default?
5. **History:** default retention 30 days, max 500 entries, excluded from Time Machine, and "Off" still keeps 24 h
   undo data. Confirm all four.
6. **CLI early subset in P2** (proposed), and the Homebrew tap: own tap first, then the main cask repo after 1.0?
7. **Notch HUD second placement** (OWN-HUD-2, §2a.6): keep today's "near the drop" placement under that name, or a
   fixed bottom-right corner? (Added 2026-10-22; items 1–6 were adopted on 2026-10-21.)

---

## 8. Prototype index (local prototypes, not published)

| Folder | Files | What it proves |
|---|---|---|
| `shelf.kibB/` | `src/shelf.swift`, `src/bm2.swift`, `src/shake.swift` | Bookmarks across rename, move, Trash and delete; bookmark option sizes and log noise; share services; multi-URL pasteboard; copy-all and move-all; shake detector accuracy on synthetic traces |
| `wheels.Lbzf/` | `src/wheels.swift` | Layout schema, validator, apply-with-cap, hostile import, palette contrast, deuteranopia ΔE |
| `history.j3qC/` | `src/json.swift`, `src/sd.swift`, `copy.ytAg/` | JSON vs SwiftData size and speed; deleted paths linger in SQLite until vacuum; 0600 permissions |
| `cli.BdWq/` | `proto/` (ArgumentParser 1.7.2 from `sap/`), `fake.app/`, `bin/` | Command shapes, JSON envelope, exit codes 1/2/3 (64 → 2 mapping), helper lookup via symlink, size cost, completions |

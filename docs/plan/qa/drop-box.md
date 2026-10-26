# QA checklist: the Drop Box and the notch tray (M5b)

Owner steps OS-M5b-1 and OS-M5b-2 in [16](../16-implementation-plan-m5b.md) §8, for the 05 rows P2-141, P2-55,
P2-142, P2-143 and the rest of P2-197. Look: [design/19c](../../design/19c-drop-box-look.md); behaviour:
[design/17e](../../design/17e-app.md) §2 and §2a. Unit and shell tests already cover the shelf core (items,
bookmarks, the store, owned copies, auto-clear), the panel's presentation and dock rules, the bulk-action targets,
the tray client against fake hosts, the proximity rule on synthetic drags and the exit runner. These rows check what
only real hardware, real drags, other apps and the system's assistive technologies show.

## Setup

- A Debug build: `make app`. Quit any running Zivlet first (`osascript -e 'quit app "Zivlet"'`).
- Settings › General › Drop Box: "Open at the notch while dragging" on, "Shake to open" off, "Clear items" off and
  "BOX on the wheel adds to" the most recent box, unless a row says otherwise.
- Debug-only flags (D-M5b-20; a Release build that carries any of them fails `make release-check`):
  `-ZivletBoxPreview <state>` shows one panel state with made-up items (hidden, docked, collapsed, grid, list,
  selection, dropTarget, busy, attention, confirmTrash, confirmClear, empty, confirmEmpty, storageWarning);
  `-ZivletTrayPreview <state>` shows one tray state (dropTarget, toast, compact, sensor);
  `-ZivletBoxDemo <absolute folder>` adds that folder's files to a demo box kept inside the folder, never in the
  person's `boxes.json`. The island's `-ZivletIslandFinish glass|solid|contrast`, `-ZivletIslandPill YES`,
  `-ZivletIslandReduceMotion YES` and `-ZivletIslandBackdrop white|black` apply to the panel and the tray too.
  `make box-states` captures every state into `build/box-states/`. The rows below use the real system settings and
  real drags, not these flags, unless they say so.
- At the top of the run, record the macOS build, the Mac model, the display modes and refresh rates, and the Zivlet
  commit.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). A fail opens an issue.

## B. Drop Box panel

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| B1 | The BOX slice | Drag two files from Finder and open the wheel; check the slice; drop on it. Repeat holding ⌥ on the slice | The slice shows `tray.full` and "BOX"; the files join the most recent box and the panel shows them; with ⌥ a new box is made and becomes the current one | |
| B2 | Show without taking focus | Type in TextEdit; choose "Show Drop Box" in the status menu | The panel appears; TextEdit stays frontmost and keeps its caret | |
| B3 | Docking | Drag the panel by its header towards the right edge of the display, then away; once move it only a few points | It docks when its edge comes within 28 pt; it leaves the dock only after 48 pt of travel; a move of a few points is a click, not a drag | |
| B4 | Grid and list | Switch views with the header button, then with ⌘1 and ⌘2 | Both views show the same items in the same order; the choice survives closing and showing the panel | |
| B5 | **200 items out to Finder** | Add 200 files to a box; select all; drag the stack into an empty Finder window in one drag | All 200 arrive; the panel stays where it is; no Zivlet window takes focus; note how long the drag took to start | |
| B6 | Promise from Mail | Drag an attachment out of a Mail message into the panel | It lands as an owned copy (the item says so in its context menu, and Box storage grows) | |
| B7 | Promise from Photos | Drag a photo out of Photos into the panel | As B6 | |
| B8 | Image from Safari | Drag an image out of a web page in Safari into the panel | As B6 | |
| B9 | Quick Look | Select an item; press Space; press Space again | Quick Look opens for the item and closes; the app being typed in before stays frontmost after it closes | |
| B10 | Keyboard | With the panel key, go through the keyboard table of 17e §2.3 (⌘A, arrows, type-to-select, ⌘C, ⌥⌘C, ⇧⌘M, ⇧⌘C, ⌘S, ⌫, ⌘⌫, Escape, ⌘W) | Each key does what the table says, and only while the panel is key | |
| B11 | Marquee, type-to-select, context menu | Drag a marquee over four cells; type the first letters of a name; Control-click an item | The marquee selects the four; typing selects the first match; the context menu offers the box commands for the selection | |
| B12 | Share and AirDrop | Share three items with Messages from the action bar; AirDrop two items to a real device | The share picker opens next to the button without activating Zivlet; AirDrop's sheet opens and the device receives both | |
| B13 | Convert all | Drag the whole stack out of the panel with the convert modifier held | The wheel opens for every item; a conversion runs for all of them | |
| B14 | Move to and Copy to | Move three items to a folder; Undo. Copy three items to a folder on another volume; Undo | Each is one entry in Undo; Move's Undo puts the files back and the box follows them; Copy's Undo puts the unchanged copies in the Trash; both work across volumes | |
| B15 | Trash, Clear, missing items | Move one item to the Trash (no question), then three (an inline question); Clear the box and press Undo within 10 s; delete one item's file in Finder and use Locate… and Remove missing | One item goes without a question; three ask "Move 3 to Trash?" inside the panel, no alert; Clear's Undo stays 10 s and brings the items back; the deleted file shows as missing, Locate… asks where the file is now and the item follows the chosen file, Remove missing removes only missing items | |
| B16 | Restore after a relaunch | With a box shown at a moved position and one docked, quit and relaunch; then move one item's file to the Trash, unmount a disk holding another, delete a third, and relaunch again | The frame, dock edge and items come back; the three items show "in the Trash", "not connected" and "missing" | |
| B17 | Storage line and the 2 GB dot | Repeat B6–B8 until the owned copies pass 2 GB; then Settings › Drop Box › "Empty Box Storage" | The overflow symbol shows the storage dot after 2 GB; the overflow menu and Settings show the same total; Empty asks once inside Settings and frees the space | |

## T. Notch tray

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| T1 | Opens only when the drag rests at the notch | Drag a file to the notch and wait; then drag a file quickly past the notch to a menu-bar item and drop it there | Resting opens the drop target ("Add 1"); the pass on the way to the menu bar opens nothing | |
| T2 | Drop at the notch | Drag three files to the notch, wait for the drop target, drop; press Undo on the toast | "Added 3" with Undo; the files join the current box; Undo takes them out again | |
| T3 | Hover and the full panel | With items in the box, rest the pointer on the housing; press the open button | The compact view opens with up to six thumbnails; the open button shows the full panel below the island | |
| T4 | **Full-screen Space** | Put Safari in full screen; drag a file to the notch and drop | The drop target shows and the drop lands in the box (this was not prototyped: note exactly what happens) | |
| T5 | External display | On a display without a notch, drag a file to the top centre and wait | The pill drop target shows at the top centre of that display; a drop lands in the box | |
| T6 | The wheel wins | Drag a file near the notch until the drop target shows; open the wheel with the trigger; move back to the notch and release over it | The tray steps aside as soon as the wheel shows; the drop goes to the wheel or nowhere, never into the tray | |
| T7 | Progress stays visible | With items in the box (the tray resting), convert a large file at the notch | The HUD's progress shows the whole time; the resting tray never hides it | |
| T8 | Pause | Pause Zivlet from the status menu; drag a file to the notch and wait; with "Shake to open" on, shake a drag | Nothing opens at the notch and the shake opens nothing until Zivlet is resumed | |
| T9 | Menu bar beside the housing | With items in the box, click the menu titles and status items nearest the housing | Every click reaches its item; the resting tray draws nothing and blocks nothing beyond the housing | |
| T10 | Setting off | Turn "Open at the notch while dragging" off; drag a file to the notch and wait | No drop target | |

## A. Look and accessibility

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| A1 | Every state | Run `make box-states`; open each picture next to 19c §4 | Each state matches 19c: no borders or dividers, SF Symbols, few words, nothing clipped or misaligned | |
| A2 | Reduce Transparency | System Settings › Accessibility › Display › Reduce transparency; show the panel, the compact view and the drop target | The glass becomes the solid finish; text stays readable | |
| A3 | Increase Contrast | Turn on Increase contrast; repeat A2 | The contrast finish: solid surfaces with a thin outline; icon buttons show their round background without hover | |
| A4 | Reduce Motion | Turn on Reduce motion; dock and undock the panel, open the drop target and the compact view | Fades instead of moving or growing shapes | |
| A5 | VoiceOver | Turn VoiceOver on; move through the panel in list view; drag a file to the notch | Rows read the item name, kind and status; every button has a label; the drop target announces "Add 1 item to the Drop Box"; the drop announces "Added 1 item" | |
| A6 | Voice Control | Say "Show Drop Box" through the menu, then "click Share" and "click Move to Trash" | Each command acts on the panel's button | |
| A7 | Light mode | Switch the system to Light appearance; show the panel and the compact view | The panel stays dark, as the island does (OP-M5b-1) | |

## C4. Reads before and after a drop

What the prototype answered (16 §3.5, run on 2026-10-26 under a throwaway app identity, outside the repository):
reading a drag's types, item count and URL strings made no file-system access and no TCC request; metadata reads
and bookmarks made without a security scope made only silent preflight checks in Downloads and none at all for an
evicted iCloud file or a disk-image volume; a security-scoped bookmark raised a real Downloads prompt, so Zivlet never
makes one (D-M5b-2). The box and the tray read nothing but the drag's types and item count before a drop (D-M5b-4,
`PreDropReadTests`); the wheel's existing payload probe is unchanged. Not settled by the prototype:

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| C4a | Dragging from protected folders | With Zivlet freshly installed (or its TCC entries reset by the owner with `tccutil reset All app.zivlet.Zivlet`), drag files from Downloads, Desktop, Documents and iCloud Drive (one evicted file among them) to the tray and to the panel | No prompt while dragging; note any prompt after the drop and which action raised it | |
| C4b | Thumbnails after a relaunch | Quit and relaunch with those items in the box; open the box | Note whether thumbnails raise a folder prompt; if so, OP-M5b-3 decides | |
| C4c | An evicted iCloud file | With an evicted iCloud file in the box, open the box, then Quick Look it | Note whether the thumbnail or Quick Look downloads it (the prototype showed metadata and bookmarks do not) | |
| C4d | A USB drive | Add files from a USB drive; eject the drive; open the box | No prompt while dragging; after ejecting, the items show "not connected", not "missing" | |

## S. Shake (opt-in)

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| S1 | Off by default | With "Shake to open" off, shake a file drag from side to side | Nothing opens | |
| S2 | On | Turn "Shake to open" on; during a file drag make four quick side-to-side swings | The panel opens under the pointer in its drop-target state; dropping adds the files | |
| S3 | A day with it on | Work normally for a day with "Shake to open" on | Note every open you did not mean (none is the goal) | |

## R. Recordings (OS-M5b-1, P2-197)

The recorder exists only in Debug builds and only when asked (D-M5b-10). It saves timings, pointer positions,
button state and the display geometry of each file drag; nothing about the files, their names or their paths. The
folder is `~/Library/Application Support/Zivlet/DragTraces/` (folder 0700, each file 0600). Nothing leaves the Mac
unless the owner commits it. The P2-197 acceptance (≥ 95 % of notch-bound drags detected, 0 accidental opens over
200 normal drags) is measured only here; the exit runner's synthetic replay (Y7) does not claim it.

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| R1 | Setup | `open -n build/DerivedData/Build/Products/Debug/Zivlet.app --args -ZivletRecordDragTraces normal` | The log shows `DragTrace: recording normal`; each file drag adds one JSON file to the folder | |
| R2 | 200 normal drags | Over a few days of ordinary work: drags to Finder windows, the Desktop, browser upload areas, Mail, the Dock and status items, on the built-in display (and an external one if at hand) | At least 200 `normal` files | |
| R3 | 50 notch-bound drags | Relaunch with `-ZivletRecordDragTraces notch`; make 50 drags aimed at the notch, waiting there as you would for the tray | At least 50 `notch` files | |
| R4 | Replay | `make drag-replay TRACES="$HOME/Library/Application Support/Zivlet/DragTraces"` | Pass: ≥ 95 % of notch-bound drags detected and 0 accidental opens. On a fail: `swift run --package-path Packages/ZivletKit zivlet-traces tune <folder>` proposes constants, and the `NotchProximity` configuration changes in one commit | |
| R5 | Keep or commit | Decide whether the traces stay local (the default) or are committed under `Fixtures/drag-traces/` | The decision is written in the M5b record | |

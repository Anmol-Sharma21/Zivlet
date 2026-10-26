# 19c — Drop Box panel and notch tray: look

Date: 2026-10-26. Status: specification for M5b, **not built**. The implementation plan is
[16-implementation-plan-m5b](../plan/16-implementation-plan-m5b.md); what gets built and seen will be recorded in
`docs/plan/17-m5b-record.md` at the end of M5b. Inputs: [00-decisions](00-decisions.md) OWN-APP-1…3, OWN-UI-1…5;
[19b-notch-look](19b-notch-look.md) (tokens, finishes, motion, contrast); [17e-app](17e-app.md) §2 (behaviour,
states, keyboard, bulk actions) and §2a.5 (tray); [19-notch](19-notch.md) §8 (how the tray plugs into the island).

This file says how the Drop Box panel and the notch tray look. It does not change what they do: behaviour stays in
17e §2 and the 05 rows P2-141, P2-55, P2-142 and P2-143. Where 17e describes a look that OWN-UI-1 replaced (an
"accent outline" for the drop target, an "amber count" for missing items), this file wins.

Clean room: no code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch or shelf app.
Prior art is described only in 17e §2.2 and §2a.2, in our own words. Liquid Glass is Apple's system material, used
through public SwiftUI API. Every string here is Zivlet's own; strings that are new in M5b are marked *new*.

---

## 1. One family, two places

The Drop Box shows in two places and looks like one thing in both:

| Place | What it is | Finish |
|---|---|---|
| **Notch tray** | The island's client for the box (19 §8). During a file drag near the notch it opens as a drop target; later, hover on the housing opens a compact view of the box | 19b D-NL1 unchanged: black where it meets the housing, a 16 pt fade, then glass. On a display without a notch: the 19b pill, all glass |
| **Drop Box panel** | A floating panel of its own, not attached to the housing: the full box with the grid or list, selection and bulk actions | Glass with the 19b scrim on all four corners, no black band (§3.1) |

Both use the 19b tokens for spacing, type, symbols, ink, motion and the accessibility fallbacks. This file adds only
what the box needs that the island does not have: a grid, a list, a docked tab, selection, and states for missing
items and confirmations.

The rule from OWN-UI-1 holds everywhere: minimal, few words, SF Symbols, no borders and no dividers, one primary and
one secondary text style per surface, contrast at least 4.5:1 for text.

---

## 2. Decisions

| ID | Decision | Why |
|---|---|---|
| D-BL1 | **Panel finish**: SwiftUI `glassEffect(.regular, in:)` on a continuous rounded rectangle of radius 24, with a black scrim at **0.5** under the content; dark colour scheme forced and `darkAqua` set on the panel, as the island does (19b D-NL2) | The panel floats over anything, like the toast and the pill. 19b measured the worst case at a 0.5 scrim: white 6.2:1 and white 0.8 4.6:1 against the 0.12 design luminance. A light panel would need a second set of measurements and would not match the island it opens from |
| D-BL2 | **Fallbacks** as 19b D-NL3: Reduce Transparency → solid grey 0.11 (`#1C1C1C`); Increase Contrast → solid plus the 1 pt white outline at 0.5; icon buttons show their round background at white 0.18 at all times under Increase Contrast | One rule for every Zivlet surface (the wheel uses the same switch) |
| D-BL3 | **Tray finishes** are the island's (19b D-NL1, D-NL4, D-NL5): black band to the housing's bottom, 16 pt fade into glass, the flare on notch displays, toast radius 18, card radius 24; on a pill display, glass with four round corners | The tray is the island; it must not look like a second thing at the notch |
| D-BL4 | **No title.** The panel has no "Drop Box" heading and no window chrome: the header is the `tray.full` symbol, the count and the total size | Few words. The symbol is the same as the wheel's BOX slice and the menu command |
| D-BL5 | **Icon-only bulk actions** in a bar at the bottom of the card, 19b D-NL9 buttons (SF Symbol, 28 pt round hit area, no border, white 0.14 on hover, 0.22 on press), each with a tooltip and an accessibility label in words. Five visible: Share, AirDrop, Copy, Move to, Move to Trash; the rest in one overflow menu | 19b F3: rows of bordered text buttons read as a dialog. OWN-UI-3: Undo and Retry are already icon-only with words as tooltips |
| D-BL6 | **Selection** is shown by a white 0.14 rounded fill behind the cell or row (radius 8), not by an outline or an accent colour; keyboard focus uses the system focus ring | No borders (OWN-UI-1); no meaning carried by colour alone (19b §7) |
| D-BL7 | **Drop target** (panel, docked tab, tray): the content behind dims to 0.4 and a centred `tray.and.arrow.down.fill` with "Add 3" appears. No outline, no accent colour (17e's "accent outline" is replaced) | OWN-UI-1. The count comes from the drag pasteboard's item count, read without touching the files (D-M5b-4) |
| D-BL8 | **Missing items** show at 0.4 opacity with a shape badge: `questionmark` (missing), `trash` (in the Trash), `externaldrive.badge.xmark` (its volume is not connected). The header gains a secondary count and two icon buttons. No amber (17e's "amber count" is replaced) | Shape, not colour (19b §7). The three causes need different help: Locate, Put Back from the Trash, or connect the drive (D-M5b-3) |
| D-BL9 | **Confirmations inline.** Move to Trash of more than one item and Clear replace the action bar with one line and two icon buttons; there is no alert | Few words, no modal, and automation never raises an alert (owner rule) |
| D-BL10 | **The tray's idle state draws nothing.** When the box has items, the tray rests on an invisible *sensor* over the housing (notch displays only); hover with the 150 ms intent delay opens the compact view. Nothing shows at the notch until then | A permanent tab under the housing would sit over app content for as long as the box has items. The housing itself is dead space (19 §1.2). Owner question OP-M5b-2 offers a visible tab instead |
| D-BL11 | **Thumbnails** are Quick Look's, made off the main thread (prototype: 251 files, longest main-thread gap 17.7 ms); until one arrives the cell shows the system icon for the item's *type* (no file read), then the thumbnail fades in (opacity, 0.12 s; instant under Reduce Motion) | A type icon needs no file access, so a restored box can draw before any read (D-M5b-14) |
| D-BL12 | **Motion** as 19b §3.4: the panel enters with opacity and a 0.96 → 1 scale from its anchor (the dock edge, the pointer, or the tray) inside the S6 spring; it leaves with opacity only. Reduce Motion: a 0.18 s fade, no scale | One motion language for the island and the box |

---

## 3. Tokens

Everything not listed here is a 19b token and keeps its value and its name (`xs` 4, `s` 8, `m` 12, `l` 16,
`rowHeight` 36, `radius.card` 24, `radius.inner` 8, `type.primary`, `type.secondary`, `type.caption`, `type.count`,
`symbol.button`, `bar`, `outline`, `fade`). The 19b tokens are shared, not copied: they move into `ZivletNotch`
(plan 16 D-M5b-22), and the box's own tokens below live next to its views in `ZivletBox`.

### 3.1 Panel

| Token | Value | Note |
|---|---|---|
| `panel.width` | 384 | `l` + 5 cells + 4 gaps + `l` = 16 + 320 + 32 + 16 |
| `panel.minHeight` | 152 | header, one grid row, the action bar |
| `panel.maxHeight` | 60 % of the display's visible height | the grid or list scrolls beyond it |
| `panel.radius` | 24 (`radius.card`) | all four corners; no flare (the panel never meets the housing) |
| `panel.scrim` | black 0.5 | as 19b D-NL2 |
| `panel.shadow` | system window shadow | the only depth cue; no outline except under Increase Contrast |
| `header.height` | 28 | symbol, count, size; view switch and overflow on the right |
| `bar.height` | 28 | the action bar's icon buttons |
| `section.gap` | `m` 12 | header to grid, grid to bar |

### 3.2 Grid and list

| Token | Value | Note |
|---|---|---|
| `cell.width` | 64 | |
| `cell.thumb` | 48 × 48, radius 8 (`radius.inner`) | Quick Look thumbnail, aspect-fit; the type icon before it |
| `cell.gap` | `s` 8 | between cells, both ways |
| `cell.nameGap` | `xs` 4 | thumbnail to name |
| `type.cellName` *new* | system 11, regular, **white** (not 0.8), one line, truncated in the middle | at 11 pt white 0.8 would be 4.6:1 on the worst glass, too close to the limit for small text; white is 6.2:1 |
| `row.height` | 36 (`rowHeight`) | list mode |
| `row.icon` | 24 × 24, radius 6 | |
| `row.layout` | icon, `s`, name (`type.primary`, gives way in the middle), size right (`type.secondary`, monospaced digits) | where the item lives is spoken, not shown (§6) |
| `selection.fill` | white 0.14, radius 8 | cell and row |
| `missing.opacity` | 0.4 | the cell or row, not the badge |
| `badge` | SF Symbol 10 semibold in a 16 pt black 0.6 circle, bottom-right of the thumbnail | the circle keeps the badge readable over any thumbnail |
| `dim.dropTarget` | content opacity 0.4 | D-BL7 |

### 3.3 Docked tab

| Token | Value | Note |
|---|---|---|
| `tab.size` | 28 × 64, against the screen edge | glass, scrim 0.5, rounded only on its inner side (radius 14) |
| `tab.content` | `tray.full` (`symbol.tab`) over the count (`type.count`) | |
| `tab.dropWidth` | 48 | during a drag over it the tab widens to show `tray.and.arrow.down.fill` |
| `dock.attach` / `dock.detach` / `dock.move` | 28 / 48 / 8 pt | 17e §2.1, unchanged |

### 3.4 Tray at the notch

| Token | Value | Note |
|---|---|---|
| `tray.dropTarget` | the island's toast frame (360 × housing + 36; pill 360 × 40) | a one-row surface: `tray.and.arrow.down.fill` (`symbol.toast`), "Add 3" primary, "12 in box" secondary right (only when the box is not empty) |
| `tray.compact` | the island's expanded frame (380 wide, height measured, at most 320) | §4.3 |
| `tray.thumb` | 40 × 40, radius 8 | the strip in the compact view, up to 6, the last one "+6" when there are more |
| `tray.sensor` | the housing's rectangle, nothing drawn | D-BL10; notch displays only |

### 3.5 Symbols

| Meaning | Symbol |
|---|---|
| the box (header, tab, menu, wheel) | `tray.full` |
| empty box | `tray` |
| drop here | `tray.and.arrow.down.fill` |
| Share… | `square.and.arrow.up` |
| AirDrop | `airplayaudio` (the wheel's own choice for AirDrop, kept for one meaning per symbol) |
| Copy (files) | `doc.on.doc` (19b) |
| Move to… | `folder` |
| Copy to… | `plus.rectangle.on.folder` |
| Copy paths | `link` (the wheel's Copy Path symbol) |
| Move to Trash | `trash` |
| Remove from box | `minus.circle` |
| Clear box | `xmark.bin` |
| overflow menu | `ellipsis.circle` |
| grid / list | `square.grid.2x2` / `list.bullet` |
| open the full panel (from the compact view) | `arrow.up.left.and.arrow.down.right` |
| Locate… | `magnifyingglass` |
| Remove missing | `minus.circle` |
| missing / in the Trash / volume not connected (badges) | `questionmark` / `trash` / `externaldrive.badge.xmark` |
| Undo, Cancel, Close, saved, failed | 19b §3.3 unchanged (`arrow.uturn.backward`, `stop.circle`, `xmark.circle`, `checkmark.circle.fill`, `exclamationmark.triangle.fill`) |

Every symbol above exists in the macOS 26 SDK's SF Symbols set; task B3 of plan 16b checks each name resolves
(`NSImage(systemSymbolName:)` non-nil), so a typo fails a test, not the screen.

### 3.6 Contrast (computed from the tokens; 19b §3.5 values)

| Pair | Ratio | Needed |
|---|---|---|
| white text (primary, cell names) on the worst glass (0.12) | 6.2:1 | 4.5:1 |
| white 0.8 (secondary: sizes, "12 in box") on the worst glass | 4.6:1 | 4.5:1 |
| white text on the solid fallback (grey 0.11) | 17:1 | 4.5:1 |
| white 0.8 on the solid fallback | 11.2:1 | 4.5:1 |
| badge symbol (white) on its black 0.6 circle over a white thumbnail | ≥ 4.6:1 | 3:1 (non-text) |
| a missing cell's name at 0.4 opacity | not a text pair: the name is decorative there; the spoken value and the header count carry it | — |
| white on black (the tray's band) | 21:1 | 4.5:1 |

A missing item's dimmed name is under 4.5:1 on purpose; it is also announced as missing and counted in the header,
so nothing depends on reading it. The plan's token test computes every row (plan 16b task B3), and the demo script
re-measures the built panel over a white backdrop (plan 16f task E3).

---

## 4. States and layout

"Left" and "right" are inside the card's 16 pt insets.

### 4.1 Panel

| State | Layout | Primary | Secondary | Buttons |
|---|---|---|---|---|
| Hidden | nothing on screen; the box persists | — | — | — |
| Docked | the tab on its edge (§3.3) | the count | — | click opens Expanded |
| Collapsed | a small card (`panel.width` × 88): up to three thumbnails fanned 6 pt apart on the left, then two lines | "12 items" | "84 MB" | open (`arrow.up.left.and.arrow.down.right`); the fanned stack drags all items out |
| Expanded, grid | header; grid; action bar | "12 items" | "84 MB" (and "2 missing" when any are) | view switch, overflow (header right); Share, AirDrop, Copy, Move to, Move to Trash (bar left) |
| Expanded, list | as grid, with rows (§3.2) | as grid | as grid | as grid |
| Selection | the action bar acts on the selection; the header shows the selection | "3 of 12" | the selection's size | as grid |
| Drop target | the card's content at 0.4; centred symbol and line | "Add 3" | — | — |
| Busy | a `bar` under the header with the percent right; the action bar is replaced by Cancel | "Moving 12 items" (*new*, from the action's verb) | "40%" | Cancel (`stop.circle`) |
| Attention | missing cells dimmed with their badge; two buttons join the header | "12 items" | "2 missing" (*new*) | Locate… (one missing item selected), Remove missing |
| Confirm | the action bar becomes one line | "Move 3 to Trash?" (*new*) or "Clear the box?" (*new*) | — | Move to Trash or Clear (the same symbol as the action), Cancel (`xmark.circle`) |
| Empty | `tray` at 28 pt, white 0.6, centred over one line | — | "Drop files here" (*new*; 17e's longer hint is not used) | — |

The result of a bulk action is not drawn on the panel: it goes to the action toast at the notch or near the drop,
by the placement setting, as every action does today (D-M5a-3). Per-item failures go to the existing action card.

### 4.2 Tray: drop target and toast

| State | Surface | Layout | Primary | Secondary |
|---|---|---|---|---|
| Drag near the notch | `.dropTarget` | `tray.and.arrow.down.fill`, `s`, text; secondary right | "Add 3" (*new*) | "12 in box" (*new*; omitted for an empty box) |
| Dropped | toast | check mark, text, Undo right | "Added 3" (*new*) | — |
| Drop refused (nothing local, every item rejected) | toast | triangle, text | the reason in Zivlet's words ("Only items stored on this Mac can be added", *new*) | — |
| Wheel showing | — | the tray withdraws (D-M5b-8): nothing at the notch while the wheel is up | — | — |

### 4.3 Tray: compact view (the tray's expanded content)

```
┌───────────── black band to the housing, 16 pt fade ─────────────┐
│  tray.full  12 items  84 MB                         ↗  ⤴         │   header: open full panel, Share
│  ▢  ▢  ▢  ▢  ▢  +6                                              │   strip: 40 pt thumbnails, drag one or all
└──────────────────────────────────────────────────────────────────┘
```

- Header: `tray.full`, "12 items" (primary), "84 MB" (secondary); right: Share (`square.and.arrow.up`), open the
  full panel (`arrow.up.left.and.arrow.down.right`).
- Strip: up to 6 thumbnails; a thumbnail drags its item, the strip's empty space drags all items; "+6" opens the
  panel. A drag from the tray holds the island (D-N13).
- Missing items are dimmed with their badge, as in the panel.
- On a pill display the same content sits in the 19b pill card (glass, four round corners).

### 4.4 Where the panel appears

| Way in | Anchor |
|---|---|
| Menu "Show Drop Box", ⌘ shortcut later, relaunch restore | its saved frame or dock edge; first time: the right edge of the menu-bar display, docked |
| BOX slice on the wheel | the drop point, clamped 12 pt inside the visible frame (as `HUDLayout` does) |
| Shake (opt-in) | under the pointer, so the drop lands in it (Drop target state at once) |
| Open from the tray | below the island, centred on it |

---

## 5. Copy

Every string the box and the tray show or speak. Existing strings keep their owner (`ActionResult`, `ActionCard`,
the Move action's toasts); new ones are marked *new*. Counts use the existing `counted(_:_:)` plural rule.

| Where | String | Spoken form |
|---|---|---|
| Header | "12 items", "1 item" | "Drop Box, 12 items, 84 megabytes" |
| Header, selection | "3 of 12" (*new*) | "3 of 12 items selected" |
| Header, attention | "2 missing" (*new*) | "2 items missing" |
| Empty | "Drop files here" (*new*) | "Drop Box, empty. Drop files here" |
| Drop target | "Add 3" (*new*) | "Add 3 items to the Drop Box" |
| Tray secondary | "12 in box" (*new*) | "12 items in the Drop Box" |
| Tray toast | "Added 3" (*new*) | "Added 3 items" |
| Refusal | "Only items stored on this Mac can be added" (*new*) | same |
| Confirm | "Move 3 to Trash?" (*new*), "Clear the box?" (*new*) | same |
| Busy | "Moving 12 items", "Copying 12 items" (*new*) | with the percent |
| Clear toast | "Cleared" (*new*) with Undo for 10 s | "Box cleared. Undo available" |
| Tooltips and labels | "Share", "AirDrop", "Copy", "Move to…", "Copy to…", "Copy Paths", "Move to Trash", "Remove from Box", "Clear Box", "More", "Grid", "List", "Open Drop Box", "Locate…", "Remove Missing" (*new* where not already a wheel or menu title) | the same words |
| Menu | "Show Drop Box" (*new*; title from 17e §2.3) | — |
| Settings › General, "Drop Box" | "Open at the notch while dragging", "Shake to open", "Clear items: Never \| After they leave the box \| After 24 hours", "BOX on the wheel adds to: The last box \| A new box" (all *new*; renamed from "New drops go to" in the M5b review, since a drop on the panel or at the notch always goes to the box it lands on, OWN-APP-1) | the same words |
| BOX slice toast | "Added 3" (*new*, as the tray's) | "Added 3 items" |
| Overflow menu, Settings | "Box storage 1.2 GB" (*new*), "Empty Box Storage" (*new*) | the same words |
| Bulk results | "Copied 12 items" (*new*), "Moved 3 to the Trash" (*new*), "Cleared" (*new*); Move keeps "Moved 12 items"; per-item lines such as "photo.heic is missing." (*new*) | the same words |
| Wheel slice | "BOX" (OWN-APP-1), symbol `tray.full` | "Drop Box" |
| Item, spoken | — | "photo.heic, 2.1 MB, in Downloads"; missing: "photo.heic, missing"; in the Trash: "photo.heic, in the Trash"; volume: "photo.heic, on Backup, not connected" |

Long names give way in the middle (as the island's `PartedLine`); sizes and counts never truncate.

---

## 6. Accessibility

| Setting or tool | Behaviour |
|---|---|
| VoiceOver | The panel is one AX list; each item is a row whose label is the spoken form in §5. Bulk-action buttons carry their words. The tray's drop target announces "Add 3 items to the Drop Box" when it opens during a drag; a drop announces "Added 3 items" |
| Voice Control | "click Share", "click Move to Trash" work through the labels |
| Keyboard | 17e §2.3's table, only while the panel is key; it becomes key on a click into the panel, never on show (prototype: showing did not change the frontmost app; a click-made key panel kept the frontmost app too) |
| Reduce Transparency | solid grey 0.11 (D-BL2), the panel and the tray alike; a shown surface changes at once |
| Increase Contrast | solid plus the outline; icon buttons always show their round background |
| Reduce Motion | fades only (D-BL12); thumbnails appear without fading |
| Colour | no meaning carried by colour: missing, in the Trash and offline differ by badge shape; selection by a fill |

Tests cannot see glass in `ImageRenderer` output (19b §7), so the plan tests the choice of finish, the tokens'
contrast, the layout on the solid finish, and the accessibility tree; glass is checked by screenshots and the
owner.

---

## 7. What the prototypes showed (outside the repository, 2026-10-26)

A throwaway AppKit program drew a sketch of the expanded panel (glass, scrim 0.5, the header, a 5-column grid of
48 pt cells, five icon buttons) and of the tray's drop target at the real notch of the 14-inch display (black band
to the housing, glass row with the drop symbol, "Add 3" and "12 in box"). Both drew as specified over a dark
backdrop. **Not seen:** either over a light window or wallpaper, the docked tab, the list, the Attention and Confirm
states, Reduce Transparency and Increase Contrast with the system settings, and any frame of the motion. Those are
for the demo script (plan 16f, task E3) and the owner's review of every state (OWN-UI-1).

---

## 8. Risks

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| 11 pt white names in a dense grid read as busy | medium / low | one line per cell, middle truncation, no extension shown when the thumbnail says the type; the owner reviews the grid screenshot; the list mode is one key away |
| Dimmed missing items are hard to tell apart from present ones on a busy wallpaper | medium / medium | badge with its own dark circle; header count; spoken state; the Attention buttons |
| Glass over light content makes 0.8 white sit at the 4.5:1 limit | medium / high | scrim 0.5 as measured in 19b; task E3 re-measures the built panel over white and fails under 4.5:1 |
| The invisible sensor confuses people who expect to see the box at the notch | medium / medium | OP-M5b-2 asks the owner; the change to a visible tab is one surface value and a view, since the arbiter already ranks a resting tab below the HUD (D-M5b-6) |
| A dark panel in Light mode looks out of place next to light windows | low / low | it matches the island it opens from; the owner reviews screenshots in Light mode |

# 19b — Notch island look: Liquid Glass, fewer words, redraw only what changes

Date: 2026-10-24. Status: built on the local branch `notch-design` by [plan 14](../plan/14-implementation-plan-notch-design.md);
what was built, measured and not seen is in [15-notch-design-record](../plan/15-notch-design-record.md). Inputs:
[00-decisions](00-decisions.md) OWN-UI-1 (2026-10-23), [19-notch](19-notch.md) (D-N3, D-N5, D-N7, D-N10, §3.4, §4.3,
§5.5), [17e-app §2a](17e-app.md), [13-m5a-record](../plan/13-m5a-record.md) (G-M5a-1, X6) and
[qa/notch.md](../plan/qa/notch.md). The implementation plan is
[14-implementation-plan-notch-design](../plan/14-implementation-plan-notch-design.md).

What changes: how the island looks and how often it redraws. What does not change: the island's rules (machine,
arbiter, holds, timings, frames, the 6 pt menu-bar rule of D-N3, the status-menu path of D-N12), the presses and their
closures, and the copy owned by `HUDCopy`, `ResultCardModel`, `BatchPresentation` and `ActionResult` unless a row
below says so. This file supersedes D-N10 for every surface below the housing (OWN-UI-1); D-N10 still holds for the
collapsed tab on a notch display, which stays solid black.

Clean room: unchanged. No code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch or
shelf app. Liquid Glass is Apple's system material, used through public SwiftUI API. Every string here is Zivlet's
own; new ones are marked *new*.

---

## 1. Audit of the M5a island

Sources: the M5a code on `main` at `0b5a5e6` (`ZivletNotch/IslandChrome.swift`, `IslandShape.swift`,
`ZivletUI/Notch/*`, the surface-free HUD content in `ZivletUI/HUD`) and the screenshots taken at the end of M5a
(collapsed with progress, saved toast, working card, result card, each alone and over a full-screen browser). States
marked "not seen" were read from the code only; nobody captured them.

### 1.1 Every visible state

| # | State | What it shows today | Seen |
|---|---|---|---|
| V1 | Collapsed tab, working | Black 232 × 62 pt shape; in the 24 pt band below the housing: the source file's Finder icon (16 pt) at the left end, a 14 pt ring (white on white 0.4) at the right end, 8 pt from the edges | yes |
| V2 | Stepped glyph | As V1 with a quarter arc in one of 8 positions | not seen (X6 sampled it) |
| V3 | Expanded working card | 380 pt wide; 38 pt black band, then 14 pt padding, "Converting to MP4" (headline), "holiday.mov · 40% · less than a minute left" (callout, white 0.8), a system linear bar in the accent colour (blue) on a near-black track, a bordered grey "Cancel" button on its own row | yes |
| V4 | Multi-job list | Up to five rows: ring or glyph, title over detail, up to two bordered text buttons per row; "+2 more" | not seen |
| V5 | Saved toast | 360 × 74 pt; check mark and "Saved srgb.jpg · 1 KB → 4 KB" (callout medium) | yes |
| V6 | Result card | 54 pt thumbnail (a blank document placeholder in the preview), "Saved photo.jpg" (headline) over "photo.jpg · 2.1 MB → 640 KB", then four bordered buttons: Undo, Reveal, Open, Copy | yes |
| V7 | Failure toast, then tab | Triangle glyph and "Reason · name"; after 4 s the tab with the triangle in place of the ring | not seen |
| V8 | Failure card | Reason, subtitle, Show Details, Retry, Close as bordered text buttons; details in a quaternary box | not seen |
| V9 | Action toast | `doc.on.doc` glyph for every action, the action's toast text, a bordered "Undo" when offered | not seen |
| V10 | Action card (partial, failed) | Title, up to five caption lines, "and 3 more", Undo, Show details, Close | not seen |
| V11 | Pill, no notch | 200 × 28 pt black capsule 6 pt under the menu bar, the same tab content; toast 360 × 40; card with four round corners | not seen in M5a (the spike's shots 05–06 are older) |
| V12 | Increase Contrast | 1 pt white outline at 0.5 inside the edge | not seen |
| V13 | Reduce Transparency | No change (the island is opaque) | not seen |
| V14 | Reduce Motion | Shape changes at once; content cross-fades for 0.18 s | not seen in M5a |

### 1.2 What is cluttered or inconsistent

| # | Finding | Where |
|---|---|---|
| F1 | The result card says the name twice: "Saved photo.jpg" over "photo.jpg · 2.1 MB → 640 KB" | V6, `ResultCardContent` with `ResultCardModel.sizeLine` |
| F2 | The working card spends four rows on one job: a title that repeats what the arrow could say, a line, a bar and a button row | V3, `WorkingContent` |
| F3 | Bordered grey text buttons (up to four in a row, two per list row) are the busiest thing on the island, and they read as a dialog rather than a status | V3, V4, V6, V8, V10 |
| F4 | The progress bar uses the accent colour on a track that almost vanishes on black (the track's contrast to black is well under 3:1); everything else on the island is white | V3 |
| F5 | The tab's Finder icon is a grey document at 16 pt on black: it says little and is the only non-white glyph in the tab | V1, `NotchIcon` |
| F6 | Every action toast uses the copy glyph, also for Move and Open in Terminal | V9, `NotchSymbol.action` |
| F7 | Spacing has no grid: 8 pt (tab), 14 pt (toast, card padding), 24 pt (card sides), 6 and 8 pt row gaps, 3 pt line gaps | `NotchTab`, `NotchToast`, `NotchCard`, `NotchList`, HUD content |
| F8 | Three text styles per card (headline, callout, caption) and symbols at 13 pt in a 16 pt box next to a 14 pt ring | all |
| F9 | 52 pt of black before the first line of the card (38 pt housing plus 14 pt padding), so the card looks top-heavy | V3, V6 |
| F10 | The island meets the screen edge with a hard vertical side; the housing itself has no such step | `IslandShape` (square top corners) |
| F11 | Separators "·" carry the structure of every line; with two text weights they are not needed | V3, V5, V6 |
| F12 | Each 1 % of progress redraws the whole chrome (outline, clip, content wrapper), not only the ring, because the chrome view reads the accessibility value it is handed (§6) | `IslandChrome`, `IslandHost.refreshAccessibility` |

---

## 2. Decisions

| ID | Decision | Why |
|---|---|---|
| D-NL1 | **Finishes.** Collapsed tab on a notch display: solid black (D-N10 unchanged). Toast and expanded card on a notch display: black from the top edge to the housing's bottom, then a 16 pt fade into Liquid Glass. Pill (no notch), all its surfaces: Liquid Glass, no black band | OWN-UI-1. The tab can rest for minutes during a long job: black keeps it one piece with the housing and costs no glass. The pill never meets a housing |
| D-NL2 | Glass = SwiftUI `glassEffect(.regular, in: IslandShape)` with a black scrim at **0.5** under the content, and the dark colour scheme forced on the chrome and `darkAqua` set on the panel | Probe §4.2: plain glass gives 3.7:1 for white text over a white window; at the small sizes of the toast and pill even a 0.35 scrim gives only 4.6:1 (primary) and 3.6:1 (secondary). A 0.5 scrim gives at least 6.9:1 and 5.1:1 at every size measured. `NSGlassEffectView` follows the window's appearance and turns light in Aqua (1.2:1), and has one corner radius for all four corners, so it cannot draw the square top |
| D-NL3 | **Reduce Transparency → solid** grey 0.11 (`#1C1C1C`) under the same black band. **Increase Contrast → solid** plus the 1 pt white outline at 0.5 | OWN-UI-1. The same rule as the wheel (`WheelAppearance.resolve`: either setting forces Solid). White on grey 0.11 is 17:1, white at 0.8 is 11.2:1 |
| D-NL4 | **Shape.** On a notch display the top outer corners flare: the shape's top edge is as wide as the frame, and a 6 pt concave curve brings each side in to the body. The body's bottom corners stay continuous. Frames from `IslandLayout` do not change, so the collapsed island still covers at most 6 pt of the menu bar beside the housing, and now only at its top edge | F10. The flare is drawn inside today's 6 pt shoulder, so D-N3's acceptance rule holds without a new layout |
| D-NL5 | **Radii** (continuous): tab 12, toast 18, card 24, pill height / 2; anything inside a card uses card radius minus its inset (thumbnail 24 − 16 = 8) | Corners concentric with the card; the tab keeps M5a's radius |
| D-NL6 | **Spacing grid of 4 pt** (§3.1). Content starts 8 pt below the housing, not 14 | F7, F9 |
| D-NL7 | **Two text styles per surface**: a primary line (13 pt semibold, white) and a secondary line (12 pt regular, white 0.8). Captions (10 pt) only for "+2 more", notes and the undo reply | F8 |
| D-NL8 | **One line per state where it fits**; structure by weight and spacing, not "·" (§5). The spoken forms keep separators as words | F1, F2, F11 |
| D-NL9 | **Icon buttons**: SF Symbols in a 28 pt round hit area, no border, no fill until hover (white 0.14) or press (white 0.22); each has a tooltip and an accessibility label equal to today's button title, so "click Undo" still works in Voice Control | F3. Titles stay the same words; only their drawing changes |
| D-NL10 | **Glyphs**: the tab shows an SF Symbol for the target's format family (photo, film, waveform, doc, table, captions, archive box) instead of the Finder icon; done actions show a check mark, not the copy glyph | F5, F6. `ActionResult` does not say which action ran, so a per-action symbol would need new data (not now) |
| D-NL11 | **Progress ink**: fill white, track white 0.3, on every finish; no accent colour on the island | F4; contrast in §3.5 |
| D-NL12 | **Redraw only when something visible changes** (§6): a snapshot whose visible content equals the last one stops in `NotchHUD.show`; progress is quantised to what the ring or bar can draw; the chrome stops reading the accessibility value | G-M5a-1, F12 |
| D-NL13 | Motion keeps M5a's springs (S6) and Reduce Motion rule (D-N5); content enters with opacity and a 0.96 → 1 scale from the top, leaves with opacity only. No `glassEffectID` morphing: the island is one shape that changes size | Probe §4.3: glass follows an animating custom shape and fades with `.opacity`; a second glass view would cost a second glass pass |

---

## 3. Tokens

All values in points. They live in two places: surface tokens (finish, scrim, flare, radii, outline) in `ZivletNotch`
next to the chrome, and content tokens (spacing, type, symbols, ink) in `ZivletUI/Notch`. The plan names the types.

### 3.1 Spacing (4 pt grid)

| Token | Value | Used for |
|---|---|---|
| `xs` | 4 | gap between icon buttons; gap between a primary and a secondary line |
| `s` | 8 | glyph to text; content below the housing; row gap in the list; tab side inset |
| `m` | 12 | toast side inset; card bottom inset; pill side inset |
| `l` | 16 | card side inset (from the body, after the flare) |
| `rowHeight` | 36 | toast row (as M5a) |
| `tabBand` | 24 | the band under the housing (as M5a) |

### 3.2 Shape

| Token | Value |
|---|---|
| `flare` | 6 (notch displays only; the pill has none) |
| `radius.tab` | 12 |
| `radius.toast` | 18 |
| `radius.card` | 24 |
| `radius.pill` | height / 2 |
| `radius.inner` | `radius.card − l` = 8 (thumbnail, details box) |
| `outline` | 1 pt, white 0.5, inset by half its width (Increase Contrast only) |
| `fade` | 16: black at the housing's bottom edge to the finish 16 pt lower |

### 3.3 Type and symbols

| Token | Value |
|---|---|
| `type.primary` | system 13, semibold, white |
| `type.secondary` | system 12, regular, white 0.8, monospaced digits for percent and sizes |
| `type.caption` | system 10, regular, white 0.8 |
| `type.count` | system 11, semibold (the tab's "3 jobs") |
| `symbol.tab` | 13 semibold in a 16 pt box |
| `symbol.toast` | 15 semibold |
| `symbol.button` | 13 medium in a 28 pt circle |
| `ring` | 16 pt across, 2.5 pt line, round caps |
| `bar` | 3 pt high, capsule |

| Meaning | Symbol |
|---|---|
| saved | `checkmark.circle.fill` |
| failed (shape, not colour) | `exclamationmark.triangle.fill` |
| format family: image, video, audio, document, spreadsheet, subtitle, archive | `photo`, `film`, `waveform`, `doc.text`, `tablecells`, `captions.bubble`, `archivebox` |
| Cancel | `xmark` |
| Undo | `arrow.uturn.backward` |
| Reveal | `folder` |
| Open | `arrow.up.forward.app` |
| Copy | `doc.on.doc` |
| Retry | `arrow.clockwise` |
| Show Details / hide | `chevron.down` / `chevron.up` |
| Close | `xmark.circle` |

### 3.4 Motion

| Token | Value | Reduce Motion |
|---|---|---|
| `expand` | spring response 0.38, damping 0.78 (S6) | no size change in view; 0.18 s cross-fade |
| `collapse` | spring response 0.32, damping 0.9 | same |
| `content.in` | opacity 0 → 1 and scale 0.96 → 1 anchored at the top, inside the shape's spring | opacity only |
| `content.out` | opacity 1 → 0, 0.12 s ease-out | opacity only |
| `button.hover` | 0.12 s ease to white 0.14 | instant |
| progress | no animation: the ring or bar jumps one quantum (§6.2) | same |

No bounce under Reduce Motion, no blur in any transition (a blur is a per-frame offscreen pass).

### 3.5 Ink and contrast

Measured worst surface (§4.2): glass with a 0.5 scrim over a white window, at the pill's and the tab's sizes,
linear luminance **0.102**. Design value with margin: **0.12**. Contrast against it (WCAG 2.x formula):

| Pair | Ratio | Needed |
|---|---|---|
| white text on the worst glass (0.12) | 6.2:1 | 4.5:1 |
| white 0.8 (secondary) on the worst glass | 4.6:1 | 4.5:1 |
| ring or bar fill (white) on the worst glass | 6.2:1 | 3:1 |
| ring fill against its track (white 0.3 over the worst glass) | 3.2:1 | 3:1 |
| white text on the solid fallback (grey 0.11) | 17:1 | 4.5:1 |
| white 0.8 on the solid fallback | 11.2:1 | 4.5:1 |
| white text on black (tab, band) | 21:1 | 4.5:1 |

Tests compute every row from the tokens (the plan's task D7), so a token change that breaks a row fails the build.
The glass row rests on a measurement, not on a formula: task D18 re-measures the built island over a white window.

---

## 4. Probe: what the SDK offers and what was measured

### 4.1 Set-up

A throwaway AppKit program outside the repository, built with `swiftc -O -target arm64-apple-macos26.0` (Swift 6.4,
Xcode 27, macOS 27.0 SDK), run on the same 14-inch MacBook Pro, M2 Pro, macOS 27.0, display at 1800 × 1169 pt, dark
appearance; the probe read safe-area top 38 and auxiliary areas (0, 1131, 790 × 38) and (1010, 1131, 790 × 38), the
same values as the M5a fixture. Borderless non-activating panels at `.statusBar` showed the island finishes over
backdrop panels of known colour (white, black, a colour gradient, black and white stripes) at `.floating`, plus one
toast-sized island at the real notch. Screenshots with `screencapture -x`; luminance read from the screenshots with
ImageMagick (linear Rec. 709 luminance of a text-free box inside each surface; the maximum in the box is used).

### 4.2 Results

| # | Question | Result |
|---|---|---|
| P1 | APIs in this SDK | SwiftUI: `glassEffect(_:in:)` taking **any `Shape`**, `Glass.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`, `GlassEffectContainer(spacing:)`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(.matchedGeometry / .materialize / .identity)`, `GlassButtonStyle` (`.glass`), `ConcentricRectangle`, `backgroundExtensionEffect()`; all macOS 26.0. AppKit: `NSGlassEffectView` (`contentView`, one `cornerRadius`, `tintColor`, `style` regular or clear; `effectIsInteractive` is **macOS 27.0 only**) and `NSGlassEffectContainerView` (`spacing`), macOS 26.0. Everything compiled with a macOS 26.0 deployment target |
| P2 | Black-to-glass blend | Works: a linear gradient, black to the housing's bottom and transparent 16–22 pt lower, drawn as content over `glassEffect(in: IslandShape)`; no seam at the housing line in the notch screenshot |
| P3 | White text over glass (dark scheme), 232 × 104 pt surface, backdrop white | plain glass: luminance 0.231, white 3.7:1, white 0.8 3.0:1 (**fails**); scrim 0.35: 0.093, 7.3:1, 5.4:1; scrim 0.55: 0.044, 11.2:1, 7.8:1; `Glass.clear` + scrim 0.55: 0.109, 6.6:1, 4.9:1 |
| P4 | Same over a black backdrop | every glass variant ≤ 0.007: ≥ 18:1 and ≥ 11.9:1 |
| P5 | Same over the colour gradient and the stripes | within 0.01 of the white backdrop's numbers for each variant (stripes: plain glass 3.6:1 at the brightest point) |
| P6 | **Glass is lighter on small surfaces** (scrim 0.35, white backdrop) | 232 × 62: 0.178 (4.6:1, 3.6:1); 360 × 74: 0.153 (5.2:1, 4.0:1); 380 × 120 and 380 × 200: 0.093 (7.3:1, 5.4:1); pill 200 × 28: 0.178 |
| P7 | Scrim 0.5 at the same sizes | 232 × 62: 0.102 (6.9:1, 5.1:1); 360 × 74: 0.089 (7.6:1, 5.6:1); 380 × 120: 0.054 (10.0:1, 7.1:1); pill 200 × 28: 0.102. Scrim 0.6: worst 0.065 (9.1:1, 6.6:1) |
| P8 | Appearance | SwiftUI glass follows the SwiftUI colour scheme (identical numbers with the app forced to Aqua). `NSGlassEffectView` follows the window's appearance: in Aqua over white it measured 0.847 (white text 1.2:1) |
| P9 | `NSGlassEffectView` shape | One radius for all corners: the top corners round off where the island must meet the screen edge square |
| P10 | Reduce Transparency | The system setting was **not** toggled (it is the owner's setting). Setting SwiftUI's environment flag for it in the probe made `glassEffect` draw an opaque surface (luminance 0.023 on every backdrop). The planned solid fallback (grey 0.11) measured 0.012: 17:1 and 11.2:1 |
| P11 | Animating shape | A custom `Shape` with animatable radius under the M5a expand spring: the glass followed the shape in every captured frame (6 frames, about 60 ms apart), including a mid-spring size and radius. Smoothness at 120 Hz was not judged (screenshots only) |
| P12 | `.opacity` on glass | The glass fades with the view: at 0.5 and 0.2 the backdrop shows through in proportion, so the host's fade-out (D-N4) still works |
| P13 | Glass over the menu bar | On a notch display the black band covers the menu-bar strip (the housing is 38 pt, the menu bar 39 pt), so glass starts below the menu bar; only the band's fade overlaps the menu bar's last point. During the probe the menu bar was black (a full-screen browser was frontmost), so glass next to a light, translucent menu bar was **not seen** |
| P14 | CPU of glass in the app | Four backdrop panels and 29 still glass surfaces: 0.35 % of a core over 60 s after 15 s to settle; the same probe with every glass surface replaced by a solid fill: 0.22 %. The cost of one island-sized surface alone and WindowServer's share were **not** measured |

What the probe did not settle: glass on macOS 26.x (only 27.0 was run), a light translucent menu bar next to the
fade, the real Reduce Transparency and Increase Contrast settings, 120 Hz smoothness, and glass pixels in
`ImageRenderer` output (tests must not rely on them; §7).

---

## 5. Copy and layout per state

Strings from `HUDCopy`, `ResultCardModel`, `BatchPresentation`, `ActionResult` and `NotchHUDCopy` stay; the table says
how they are split over the two text styles. New strings are marked *new*. "Left" and "right" are inside the body.

| State | Layout | Primary | Secondary | Buttons | Spoken (VoiceOver value) |
|---|---|---|---|---|---|
| Tab, one job | family symbol left, ring or stepped glyph right | — | — | — | unchanged (D-M5a-4) |
| Tab, several | symbol left, "3 jobs" centre, combined ring right; triangle if any failed | "3 jobs" | — | — | unchanged |
| Toast, saved | check mark, then text | "Saved photo.jpg" (gives way) | "2.1 MB → 640 KB" | — | "Saved photo.jpg, 2.1 MB to 640 KB" |
| Toast, failed | triangle, then text | the reason, without its full stop | the file name (gives way) | — | reason, name |
| Toast, action | check mark (done) or triangle (partial, failed) | the action's toast ("Copied") | — | Undo when offered | the toast |
| Card, working | row 1: family symbol, name and target, percent right; row 2: bar, time left right | "holiday.mov → MP4" (name gives way) | "40%"; "< 1 min" | Cancel | "Converting to MP4, holiday.mov, 40%, less than a minute left" (unchanged) |
| Card, saved | thumbnail 40 pt left; two lines; buttons on the right of the second line when they fit, else a row below | "Saved photo.jpg" | "2.1 MB → 640 KB"; notes and the undo reply as captions | Undo, Reveal, Open, Copy | unchanged |
| Card, failed | triangle; reason up to two lines; details box (radius 8) when shown | the reason | the file name | Show Details, Retry, Close | unchanged |
| Card, action partial or failed | glyph; title; up to five caption lines, "and 3 more" | the card's title | its lines | Undo, Show details, Close | unchanged |
| List row | ring or glyph, one line, buttons right | the row's title (gives way) | percent, size line or "Failed" (*new* for the failed row's short status) | as M5a per status (Cancel; Reveal, Open; Retry, Close; Close; Undo) | unchanged |
| "+2 more" | caption under the rows | — | "+2 more" | — | unchanged |
| Pill | the tab's content in a 200 × 28 glass capsule; the toast and card on glass with four round corners | as above | as above | as above | unchanged |

New strings: "→ MP4" after the name joins the existing name and `HUDCopy.title` target (the arrow is spoken "to");
the short time left (*new*): "almost done", "< 1 min", "3 min", "2 hr", from the same thresholds as
`HUDCopy.timeLeft`, whose long form stays the spoken one; "Failed" for a failed list row (*new*). Nothing else is new.

Long names: the primary line gives way in the middle (as M5a, `PartedLine`); the secondary line and the percent never
truncate.

---

## 6. Redraw only when something visible changes (G-M5a-1)

### 6.1 What the profile shows

Debug app from the last M5a build, `-ZivletIslandPreview progress` (a snapshot every 100 ms, 0.2 % per tick), on a
Mac at load average 1.7–2.8: **1.03 %** of a core over 30 s (no baseline taken in this run; M5a's baselines were
0.000–0.042 %). A 20 s `sample` of the same state: the main thread was busy in about 147 of 15,405 samples:

| Share | Where |
|---|---|
| 54 samples (37 %) | the preview's own driver task: building the next snapshot (7), `NotchHUD.show` (29: the board transition 13, `apply` 6 of which go to `IslandHosts.accessibilityChanged`), task wake-up and the rest |
| 50 samples (34 %) | SwiftUI's view-graph update after each publish: `IslandChrome.body` (10), `NotchTab.body` (5), layout |
| 27 samples (18 %) | AppKit's display cycle: a window layout pass (18) and the Core Animation commit |
| about 16 | other main-queue work |

So the cost is not one hot spot but repeated work:

1. **Every snapshot runs a full board transition**, including the derived requests, shapes and toast lines, although
   four of five ticks change nothing on screen (a percent moves every 5 ticks; the rough time-left string every
   few seconds).
2. **Each drawn change re-evaluates the whole chrome.** `IslandHost.refreshAccessibility` sets the chrome model's
   accessibility value, and `IslandChrome.body` reads it, so SwiftUI rebuilds the shape, the outline, the clip and the
   content wrapper, not only the tab's ring.
3. **A window layout pass and a commit follow each publish**, whatever changed.
4. The preview driver itself (37 % of the busy samples) is test scaffolding: a real conversion's snapshots come from
   `ProgressSink`, throttled to 10 Hz, without building snapshots on the main thread. X6 still counts it, so the
   numbers are an upper bound for real jobs.

The ring is not the problem by itself: the 14 pt ring's stroke runs about 44 pt (88 px at 2×), so 1 % is just under a
pixel.

### 6.2 The change

- **Visible key.** A pure `NotchHUDBoard.VisibleKey` per item: kind and status, current item name, the quantised
  progress of the ring and of the bar, the short and long time-left strings, output and failure counts, finished or
  not. `NotchHUD.show` compares the new snapshot's key with the item's last key and returns at once when they are equal
  (no transition, no host call, no publish). Finishing, failing, a new item and a new current file always differ.
- **Quanta.** Progress is quantised to the drawn length: `steps = min(100, floor(length in device pixels))`. The
  16 pt ring (about 50 pt of stroke) and the card's bar get 1 % steps at 2× and 2 % steps on a 1× display; a smaller
  glyph would get fewer. The visible key compares quantised values, so a sub-step change is not a change. With the
  existing 250 ms floor of D-N7 the tab redraws at most 4 times a second, and for the preview's rate about twice a
  second.
- **Chrome split.** The island group's label, value and action move to a small `IslandAccessibility` modifier with
  its own observable model, so a new spoken value updates one modifier and never the chrome's body. The value is still
  refreshed on every drawn change, so VoiceOver reads what is drawn (§5.5 of design/19).
- **Equality before publish.** `NotchHUD.apply` already publishes only on a drawn change; with the visible key in front
  of it, nothing reaches it between drawn changes.
- **Window layout pass.** If the 18 samples of AppKit layout per redraw remain after the three changes, the plan's task
  D5 tries `NSHostingView.sizingOptions = []` on the measurer as well and a fixed-size container for the tab, and
  records the result either way.

### 6.3 How it is measured

`make notch-idle` (X6) as in M5a, Debug app, 120 s per state after 10 s, minus the baseline; plus the same states on a
**Release** build (`make notch-idle CONFIG=release`). The island preview is Debug-only today; the plan adds a compile
condition `ZIVLET_ISLAND_PREVIEW` that only the measurement build sets, and `make release-check` fails if the shipped
Release binary contains the preview flag. New rows: toast still and card still (glass, nothing changing; limit 0.1 %),
and the pill collapsed with progress (glass; limit 1 %). Limits stay as in M5a (hidden and still states 0.1 %, progress
and stepped glyph 1 %), on both builds. WindowServer's CPU over the same windows is recorded for information only (no
limit), because the glass is composited there.

---

## 7. Accessibility

| Setting or tool | Behaviour |
|---|---|
| Reduce Transparency | solid grey 0.11 below the black band (D-NL3); read from `NSWorkspace.accessibilityDisplayShouldReduceTransparency` and its change notification, applied at the next surface change |
| Increase Contrast | solid plus the 1 pt outline; icon buttons show their round background at white 0.18 at all times, so they are visible without hover |
| Reduce Motion | D-N5 unchanged; content transitions use opacity only (§3.4) |
| VoiceOver | label, value, custom action and announcements unchanged; icon buttons carry today's titles as labels |
| Voice Control | "click Undo", "click Retry" work through the labels; tooltips show the same words on hover |
| Keyboard | Tab order left to right through the icon buttons, then the details text; Escape as M5a |
| Colour | no meaning carried by colour; the failure glyph differs from the check mark by shape |

Tests cannot see glass in `ImageRenderer` output reliably, so the plan tests the *choice* of finish (a pure function of
surface, display and settings), the tokens' contrast (computed), the shape's path, and the layout of content views
rendered on the solid finish; the glass itself is checked by screenshots (task D18) and owner QA.

---

## 8. Risks

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Glass gets lighter on small surfaces than the probe's sizes, or on macOS 26.x | medium / high (text below 4.5:1) | scrim 0.5 from the smallest measured size; task D18 measures the built toast and pill over a white window and fails under 4.5:1; owner row Q27 on light wallpapers |
| A light, translucent menu bar next to the black band looks heavy | medium / low | the band is today's look; Q28 records a screenshot on a light wallpaper for the owner |
| `NSGlassEffectView` or a light appearance sneaks in | low / high (1.2:1) | SwiftUI glass only; the panel sets `darkAqua`; a test asserts the panel's appearance |
| Glass costs CPU or GPU while the pill rests for minutes | low / medium | new X6 row for the pill with progress; the notch tab stays black |
| Icon-only buttons are less clear than words | medium / medium | well-known symbols only, tooltips, labels; owner reviews screenshots of every state before merge (OWN-UI-1); words can return per button without other changes |
| The CPU fix still misses 1 % in the Debug build | medium / low | the Release build is measured too; the record states both and what remains |
| `ImageRenderer` cannot show glass | high / low | tests avoid glass pixels (§7) |

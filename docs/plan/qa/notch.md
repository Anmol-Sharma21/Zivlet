# QA checklist: the notch island and the Notch HUD (M5a)

Owner step OP-4 in [12](../12-implementation-plan-m5a-notch.md) §7, rows Q1–Q22 of
[design/19](../../design/19-notch.md) §10, Q23–Q26 added after the M5a review, and Q27–Q32 for the design pass of
[plan 14](../14-implementation-plan-notch-design.md) ([design/19b](../../design/19b-notch-look.md)). Unit and shell tests already cover the island's rules (layout, the
machine, the arbiter, the board, the presenter on off-screen displays) and the exit runner covers one conversion at
the notch and one near the drop. These rows check what only real hardware, a real pointer and the system's
assistive technologies show.

## Setup

- A Debug build: `make app`. Quit any running Zivlet first (`osascript -e 'quit app "Zivlet"'`).
- Settings › General › Progress and results: "At the notch" unless a row says otherwise. For a one-off run without
  changing the setting: `open -n build/DerivedData/Build/Products/Debug/Zivlet.app --args -ZivletHUDPlacement notch`.
- Made-up jobs without a drop: add `-ZivletIslandPreview collapsed|progress|indeterminate|expanded|result|failure`,
  or `savedToast|failureToast|actionToast|list`. Debug-only screenshot flags (plan 14 D-ND4), which leave the system
  settings alone: `-ZivletIslandFinish glass|solid|contrast`, `-ZivletIslandPill YES`, `-ZivletIslandReduceMotion YES`,
  `-ZivletIslandBackdrop white|black`. `make notch-states` captures every state into `build/notch-states/`. The rows
  below use the real system settings, not these flags.
  A real conversion: `make convert-demo FILE=/abs/file.heic TO=jpg PLACEMENT=notch`.
- At the top of the run, record the macOS build, the Mac model, the display modes and refresh rates, and the Zivlet
  commit.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). A fail opens an issue.

## A. Pointer and hover

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q1 | Hover intent, grace and frame swaps | With a job collapsed at the notch (`-ZivletIslandPreview collapsed`): move the pointer across the notch on its way to the menu bar; then rest on the island; then leave it. Then, one at a time: (a) move near the shape while it collapses; (b) let it collapse under a still pointer, move away, come back; (c) start a preview with the pointer already resting where the island appears; (d) re-enter while it collapses | Crossing opens nothing; resting opens after about 150 ms; leaving collapses it after the grace. (a) does not re-open it; (b) leaves no stale hover and the next visit opens normally; (c) opens after the intent delay without moving; (d) re-opens unclipped. Note whether 150 ms / 300 ms feel right (OP-3) | |
| Q2 | Buttons keep the typing app's focus | Type in TextEdit; while a job runs at the notch, press Cancel; after a result, press Undo, Reveal, Open and Copy | TextEdit stays frontmost with its caret after Cancel, Undo and Copy (Reveal and Open bring Finder or the viewer forward, as on today's card) | |
| Q3 | Escape after a click into the details | Open a failure card (`-ZivletIslandPreview failure`), click into its text, press Escape | The card closes and the island goes away (G-M4-10) | |
| Q4 | Drag the result out | Convert a file at the notch; hover the island to open the card; drag the thumbnail into Finder, a Mail draft and Messages; once drag slowly for more than 4 s | Each target gets the file; the island stays open during the whole drag; after the drop the toast lingers its full 4 s | |

## B. Menu bar, full screen, Spaces and displays

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q5 | Full screen | Run a preview while Safari, Keynote and a full-screen video are each in full screen | The island shows in the black strip; moving to the top still slides the menu bar in, and the island does not block it | |
| Q6 | Auto-hiding menu bar | System Settings › Control Centre › hide the menu bar automatically on the desktop; run a preview | The island neither reveals the menu bar nor blocks it from appearing | |
| Q7 | External display without a notch | Connect one; convert by dropping on the external display, then on the built-in one | The external drop shows the pill at the top centre of the external display; the built-in drop shows the island at the notch | |
| Q8 | Lid closed | Close the lid with the external display attached; convert | The pill on the external display; Settings still says "At the notch" | |
| Q9 | Stage Manager | Turn on Stage Manager; run each preview | The island stays put and never becomes a stage window | |
| Q10 | Spaces and Mission Control | With a job collapsed, switch Spaces and open Mission Control | The island stays where it is and does not animate away | |
| Q13 | Crowded menu bar | Fill the menu bar (many status items, an app whose menus reach the notch); run the collapsed and toast previews | The collapsed island covers no menu title or status item and never blocks a click on one; a toast may cover them for its few seconds. Save a screenshot for OP-6 | |
| Q14 | Screen sharing and recording | Share the screen in a call and record it with the Screenshot app while a preview runs | What the island shows is acceptable to share | |
| Q15 | Other notch sizes | On a 16-inch MacBook Pro and in two more scaled modes: Settings › Advanced › Copy Diagnostics | The Displays section lists each display with its housing; paste the lines into a new fixture | |
| Q17 | 120 Hz | On a ProMotion display, hover the collapsed island repeatedly | The expand spring looks smooth, with no visible dropped frames | |

## C. Accessibility and keyboard

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q11 | VoiceOver | Turn VoiceOver on; convert one file that saves and one that fails; run a Copy action; move VoiceOver focus to the island and away | Announcements: the start, "Saved …" and the toast at normal priority, the failure at high priority; the collapsed island reads "Zivlet progress and results" and its full text; the toast reads "2.1 MB to 640 KB", not an arrow; focus opens and holds the card, moving away collapses it; toasts last three times as long | |
| Q12 | Display options | Turn on Reduce Motion, then Increase Contrast, then Reduce Transparency; hover a preview each time | Reduce Motion: a fade, no growing shape, and content only fades in (no scale). Increase Contrast: the toast and card turn solid grey under the black band, a thin white outline runs round every surface (the tab included), and the icon buttons show their round background without hover. Reduce Transparency: the toast and card turn solid grey under the black band; the tab stays black | |
| Q18 | Keyboard only | Without touching the pointer: Control-F8 to the status menu, choose "Show Progress and Results"; Tab through the card; Escape | The island opens with keyboard focus; Tab reaches Cancel, Undo, Reveal, Open, Copy and Retry as the job offers them; Escape closes it; Cancel and Undo also work from the status menu | |
| Q19 | Voice Control | Say "Show Progress and Results" through the menu, then "click Undo" and "click Retry" in the island | Each command acts on the island's button | |
| Q20 | Switch Control | Reach the island through the status menu or its accessibility action and press Undo before the toast leaves | Undo works; toasts last three times as long while Switch Control runs | |

## D. Behaviour over time

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q16 | Settings apply to the next job | Start a long conversion at the notch; switch Settings to "Near the drop"; start another | The running job stays at the notch; the new one shows near its drop | |
| Q21 | A failure while typing | Type in another app; let a conversion fail (convert a damaged file) | A toast with the error glyph, then the tab with the error glyph; no card opens by itself and the typing app keeps focus; hovering opens the card with Retry | |
| Q22 | Sleep and wake | Sleep the Mac while a saved toast shows, and again while a failure waits in the tab; wake | On wake the saved toast is gone; the failure tab is still there (D-N11) | |

## E. After the M5a review fixes ([13 §9](../13-m5a-record.md))

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q23 | The keyboard goes back when the card goes | Type in TextEdit; open a failure card by hover (`-ZivletIslandPreview failure`), click into its details text, then move the pointer away and wait for the card to collapse; type | The characters go to TextEdit, not to the island | |
| Q24 | The card grows evenly | Hover the collapsed tab and the toast several times; record the screen and step through the first frames | The island grows from the housing to both sides at once, with no sideways jump; the corners round as it grows; the old content fades into the new | |
| Q25 | Long names | Convert a file whose name is about 80 characters at the notch; let one with a long name fail; watch a long one run with the card open | The saved toast keeps the sizes and the extension; the failure toast keeps the whole reason (without its full stop) and shortens the name beside it; the working line keeps the percent and the time left | |
| Q26 | A new display mode under the island | With a job collapsed, and again with the card open, change the built-in display's scaled resolution in System Settings › Displays | The island moves under the housing at once; no content sits behind the camera; the card's corners and inset match the new mode | |

## F. After the design pass ([plan 14](../14-implementation-plan-notch-design.md))

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q27 | Glass legibility | Light wallpaper, then dark, then a busy photo; show a saved toast, a working card and the pill (`-ZivletIslandPill YES`); repeat with a text-heavy window (a terminal, a web page) right under the pill's card | All text readable; no part of a line looks washed out; note whether window text behind shows through the glass | |
| Q28 | The band meets the menu bar | Light wallpaper with a translucent menu bar; open a card; screenshot | No seam between the housing and the band; the black beside the housing is acceptable (owner's call) | |
| Q29 | The flare | Collapsed and expanded on the notch; look closely at the top corners; a crowded menu bar | The island grows out of the screen edge; it covers no menu title or status item while collapsed (Q13 still holds) | |
| Q30 | Icon buttons | Hover each button; Voice Control "click Undo", "click Reveal", "click Retry"; Tab through them | Tooltips show today's words; Voice Control finds every button; the focus ring is visible | |
| Q31 | Light appearance | Switch macOS to Light, show a toast and a card | The island stays dark with white text | |
| Q32 | Motion | Hover the tab and the toast; with Reduce Motion on, again | Content grows in with the shape; under Reduce Motion only fades | |

## G. After the design review ([15 §8](../15-notch-design-record.md))

Screenshots of every state below come from `make notch-states` (`build/notch-states/`, not tracked); the owner looks
at them before merge (OWN-UI-1). The rows that need a real job or a real setting are checked by hand.

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q33 | Every state's picture | Run `make notch-states`; open `notch-jobs-glass`, `notch-failedTab-glass`, `notch-doneTab-glass`, `notch-actionCard-glass`, `notch-failureDetails-glass`, `notch-indeterminateCard-glass`, `notch-resultFiles-glass`, `pill-jobs-glass`, `pill-list-glass`, `pill-result-contrast` | "3 jobs" with one ring; the triangle in the failed tab; the check mark in the done tab; the action card shows five lines and "and 3 more"; the details box with the inner radius; "12.4 MB written" in the unknown-length card; "Saved 3 files" with the note as a caption; the pill's tab glyphs 12 pt from its ends; the pill's card and list 16 pt from its sides | |
| Q34 | A cancelled batch | Drop a long video at the notch, open the card and press Cancel (the stop symbol) | The toast and the card show the stop glyph with "Cancelled" and "Nothing was saved."; only Close is offered; no triangle, no check mark | |
| Q35 | The outline under Increase Contrast | Turn on Increase Contrast with the tab, a toast and a card showing on the notch | One continuous thin line down each lip, side and along the bottom; no line along the screen edge beside or across the housing; no seam where a lip meets a side | |
| Q36 | Settings while a card is open | Let a conversion fail so its card stays; open it and keep the pointer on it; turn on Reduce Transparency, then Increase Contrast, then both off | The open card changes finish at once each time (solid grey, then outlined), and its buttons' resting circle appears and goes with the outline | |
| Q37 | The open card's percent | Watch a long conversion with the card open | The percent counts every whole number (no 48 → 50 jumps); the time left changes as soon as its text would; the collapsed ring still moves smoothly | |
| Q38 | VoiceOver on the island | With VoiceOver on, move through a card and the list | The family and status symbols are not read before the text; the working card's bar is read as a progress indicator with its value | |

## Known gaps to look at during the run

- Glass shows what lies behind it, blurred: in the design pass's screenshots, a terminal's title under the pill's
  result card showed faintly through the glass at the height of the second line (Q27). The contrast check over a
  plain white panel cannot see this; the scrim (0.5) is one token if the owner wants less of it.

- Show Progress and Results and the accessibility action now hold a saved result while the island has the keyboard
  (D-M5a-19); clicking elsewhere gives the keyboard back and the full linger starts again. Note in Q18–Q20 whether
  that is long enough.
- A drag of the thumbnail now holds the island from the drag's start to its end (Q4).

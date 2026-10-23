# QA checklist: the notch island and the Notch HUD (M5a)

Owner step OP-4 in [12](../12-implementation-plan-m5a-notch.md) §7, rows Q1–Q22 of
[design/19](../../design/19-notch.md) §10. Unit and shell tests already cover the island's rules (layout, the
machine, the arbiter, the board, the presenter on off-screen displays) and the exit runner covers one conversion at
the notch and one near the drop. These rows check what only real hardware, a real pointer and the system's
assistive technologies show.

## Setup

- A Debug build: `make app`. Quit any running Zivlet first (`osascript -e 'quit app "Zivlet"'`).
- Settings › General › Progress and results: "At the notch" unless a row says otherwise. For a one-off run without
  changing the setting: `open -n build/DerivedData/Build/Products/Debug/Zivlet.app --args -ZivletHUDPlacement notch`.
- Made-up jobs without a drop: add `-ZivletIslandPreview collapsed|progress|indeterminate|expanded|result|failure`.
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
| Q12 | Display options | Turn on Reduce Motion, then Increase Contrast, then Reduce Transparency; hover a preview each time | Reduce Motion: a fade, no growing shape. Increase Contrast: a thin white outline. Reduce Transparency: no change (the island is solid black) | |
| Q18 | Keyboard only | Without touching the pointer: Control-F8 to the status menu, choose "Show Progress and Results"; Tab through the card; Escape | The island opens with keyboard focus; Tab reaches Cancel, Undo, Reveal, Open, Copy and Retry as the job offers them; Escape closes it; Cancel and Undo also work from the status menu | |
| Q19 | Voice Control | Say "Show Progress and Results" through the menu, then "click Undo" and "click Retry" in the island | Each command acts on the island's button | |
| Q20 | Switch Control | Reach the island through the status menu or its accessibility action and press Undo before the toast leaves | Undo works; toasts last three times as long while Switch Control runs | |

## D. Behaviour over time

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| Q16 | Settings apply to the next job | Start a long conversion at the notch; switch Settings to "Near the drop"; start another | The running job stays at the notch; the new one shows near its drop | |
| Q21 | A failure while typing | Type in another app; let a conversion fail (convert a damaged file) | A toast with the error glyph, then the tab with the error glyph; no card opens by itself and the typing app keeps focus; hovering opens the card with Retry | |
| Q22 | Sleep and wake | Sleep the Mac while a saved toast shows, and again while a failure waits in the tab; wake | On wake the saved toast is gone; the failure tab is still there (D-N11) | |

## Known gaps to look at during the run

- A card opened with "Show Progress and Results" or the accessibility action, with no pointer over it, still leaves
  when a saved result's 4 s linger ends; only hover, VoiceOver focus or a drag hold it (D-N13). Note in Q18–Q20
  whether this is a problem.
- Dragging the thumbnail out of the island is held by the pointer being over the island when the drag starts; the
  island does not yet get a separate drag-began event (Q4 says whether that is enough).

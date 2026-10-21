# QA checklist: actions, app location, login item, usability and real-hardware numbers

Owner step O-6 in [10](../10-implementation-plan-m4.md) §7. These are the M4 rows that only a person can check on a
real Mac: the **[QA]**-gated action rows (05 P1-44, P1-45), Move to Applications and launch at login, the onboarding
usability run (P1-47), the hardware numbers (P1-63), and the on-screen contrast checks the M4 review asked for. The
trigger, wheel, cancel and onboarding-practice rows are in [trigger.md](trigger.md). Unit, script and matrix tests
already cover the planners, the executors on temporary folders and disk images, and the card models. This list
checks what the system and other people add.

## Setup

- A build of Zivlet: `make app` (Debug) for sections A–D and F, and the DMG from `make release-dry-run` for E.
  Onboarding is finished unless a row says otherwise.
- At top of the run, record the macOS build, the Mac model, the display refresh rate(s) and the Zivlet commit.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). A fail opens an issue.

## A. AirDrop (P1-44, 10d C3)

| # | Check | Steps | Expected |
|---|---|---|---|
| A1 | One file to a nearby device | Drag a PNG, tap ⌃, drop on AirDrop, pick an iPhone or another Mac | The system AirDrop sheet opens; the file arrives on the device; the toast says "Sent with AirDrop" |
| A2 | Several files | Same with three files | All three arrive in one transfer |
| A3 | Declined on the device | Decline on the receiving device | No crash; record what Zivlet shows (the sheet decides what it reports) |
| A4 | Closed without sending | Open the sheet and close it | Nothing is shown (a cancel is silent) |
| A5 | AirDrop off on this Mac | Control Centre › AirDrop › No One; repeat A1 | Either the sheet explains it, or the card says "Zivlet couldn't start AirDrop for these files."; nothing hangs |

## B. Open in Terminal, each terminal (P1-45, P-TERM)

For each terminal: install it, choose it in Settings › General › Terminal, drag a file, tap ⌃, drop on Terminal.

| # | Terminal | Expected |
|---|---|---|
| B1 | Terminal (default) | A new window or tab opens in the file's folder (`pwd` shows it); a folder dragged opens in that folder; the toast says "Opened in Terminal" |
| B2 | iTerm2 | as B1 |
| B3 | Ghostty | as B1 |
| B4 | WezTerm | as B1 |
| B5 | Warp | as B1 |
| B6 | Chosen terminal uninstalled | Remove the chosen terminal; repeat | A card names the terminal that is missing; nothing opens |
| B7 | No prompt | On a fresh account, B1 | No permission prompt (Zivlet asks the system to open the folder with the terminal; it does not script it) |

## C. Move Here, cross-volume Move and Undo (P1-45, 10d C4, C5)

| # | Check | Steps | Expected |
|---|---|---|---|
| C1 | Move Here panel | Drag two files, tap ⌃, drop on Move | The Move Here panel opens; pick a folder on the same volume; both files move; toast with Undo |
| C2 | Undo on the same volume | Press Undo within 4 s | Both files are back at their old paths with the same dates; the toast says so |
| C3 | Cross-volume move | Repeat C1 with a folder on an external drive or a disk image | Files copy, then the originals go away; toast with Undo |
| C4 | Cross-volume Undo | Press Undo | Files are back on the first volume; the copies on the other volume are moved to the Trash (check the Trash of that volume) and nothing else is touched |
| C5 | Undo after the drive is gone | Repeat C3, eject the drive, press Undo | A card says what could not be undone; nothing is lost; Undo stays only if retrying can help |
| C6 | Name clash | Move a file into a folder that already has one of that name | The moved file gets the next free name (`name 2`); the existing file is untouched |
| C7 | Double-click Undo | Press Undo twice quickly on a Move toast and on a conversion card | One undo happens; the reply is the real one, never "This can no longer be undone." |
| C8 | Card after a conversion undo | Convert a file, press Undo on the card | The card shows the undo sentence, no longer offers Reveal, Open or Copy for the trashed file, and leaves on its own after about 4 s |
| C9 | Copy and Copy Path | Copy a file, paste in Finder; Copy Path, paste in a text editor | The file is pasted; the path is the full POSIX path |

## D. Move to Applications and launch at login (03b §8.2 page 7, 03b §8.4)

| # | Check | Steps | Expected |
|---|---|---|---|
| D1 | Offered from the disk image | Open Zivlet from the mounted DMG; finish onboarding up to the last page | Page 7 offers Move to Applications |
| D2 | Move | Press it | The button waits with "Copying…" (the window does not beachball); Zivlet quits and the copy in /Applications opens; only one Zivlet in the menu bar |
| D3 | Copy fails | Make /Applications not writable for the test account (or fill the disk image's target volume); press Move | A sentence says what to do; this copy keeps running; nothing named Zivlet is left in /Applications |
| D4 | Already there | With a copy in /Applications, run from the DMG and press Move | "Zivlet is already in Applications. Quit this copy and open that one." |
| D5 | Launch at login | From /Applications: Settings › General › Open at login on; log out and in | Zivlet starts once, without onboarding |
| D6 | Approval | If macOS asks for approval in System Settings › General › Login Items | The Settings row shows the approval line; approving turns it on |
| D7 | Practice keeps the choice | Turn Open at login off in Settings; menu › Practice; Continue to the end; Finish | The login item stays off |

## E. Release DMG on a clean Mac (P1-53, O-1)

| # | Check | Expected |
|---|---|---|
| E1 | Open the notarized DMG on a Mac that never ran Zivlet | No Gatekeeper warning beyond the normal "downloaded from the internet" prompt |
| E2 | Convert one file of each kind (image, audio, video) | Each saves and the card shows sizes; no prompt other than folder access |
| E3 | Copy Diagnostics | Settings › Advanced › Copy Diagnostics with Settings open | The window stays responsive; the pasted report has no full home paths |

## F. On-screen contrast (NFR-14, FR-26; the M4 review)

Measure with Digital Color Meter set to "Display in sRGB" (not "native values"), and compute the contrast of text
and background pixels (WCAG 2). Use a white window, a light-coloured desktop picture and a dark one behind the panel.

| # | Check | Expected |
|---|---|---|
| F1 | Result card over a white window, light mode and dark mode | Title, size line and notes ≥ 4.5:1 |
| F2 | Progress HUD over a white window | Title and the progress line ≥ 4.5:1 |
| F3 | Failure card with details shown | Details text ≥ 4.5:1 |
| F4 | Action toast and card over a white window | ≥ 4.5:1 |
| F5 | Wheel hot-petal label, Glass and Solid, with the Blue, Red, Graphite and Pink accents | ≥ 4.5:1 on the pixels next to the glyphs |
| F6 | Escape on a card | Click into a failure card's details, press Esc | The card closes |

## G. Onboarding usability (P1-47)

Five people who have not seen Zivlet, each on a Mac with a fresh account or `-ZivletResetOnboarding YES`. Give them
only: "This app converts files you drag. Set it up and convert a photo to PNG." Do not help.

| # | Tester | Finished unaided? | Time | Where they hesitated |
|---|---|---|---|---|
| G1 | 1 | | | |
| G2 | 2 | | | |
| G3 | 3 | | | |
| G4 | 4 | | | |
| G5 | 5 | | | |

Pass: all five finish unaided.

## H. Hardware numbers (P1-63)

| # | Check | How | Budget |
|---|---|---|---|
| H1 | Tap → wheel p95 on a 120 Hz display | Instruments, Logging template, the `trigger→frame` signposts over 50 real drags and taps (Debug build) | ≤ 16 ms |
| H2 | `make bench` on an M1 MacBook Air | Writes `docs/plan/perf/baseline-<model>.json` on the first run; commit it | HEIC → JPEG ≤ 150 ms; 1-min MOV → MP4 ≤ 10 s; drop → HUD ≤ 50 ms; idle wake-ups 0 |
| H3 | XCUITest target (D-M4-14) | `xcodebuild test -scheme Zivlet` after granting automation | all pass |

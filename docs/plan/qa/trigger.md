# QA checklist: trigger, wheel and cancel paths with real drags

Owner step O-6 in [10](../10-implementation-plan-m4.md) §7, for 05 P1-42 (mode switching and cancel paths) and P1-64
(real-drag matrix). These are the transitions from [03a §1.4](../03a-system-design-interaction.md) that only a person
with a real pointer, real apps and real displays can check. Unit tests already cover the machine (T1–T19), the store
(highlight reset on a switch, the Reduce Motion fade) and the host plan; this list checks what the operating system adds.

## Setup

- A signed build of Zivlet from `make app` (Debug is fine), onboarding finished, default keys (⇧ Convert, ⌘ Tools,
  ⌃ Actions) unless a row says otherwise.
- Sound and haptics on (Settings › General); a Force Touch trackpad for the haptic rows.
- Record the macOS build, the Mac model, the display refresh rate(s) and the Zivlet commit at the top of the run.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). A fail opens an issue.

## A. Opening, switching, closing (one Finder window, one display)

| # | Transition | Steps | Expected |
|---|---|---|---|
| A1 | T1–T8 open | Drag one PNG from Finder, tap ⇧ once while moving | Convert wheel opens centred on the pointer within a frame; the tick plays on the first highlight |
| A2 | T8 held key | Hold ⇧, then start dragging; keep holding | No wheel (a key held before the drag is ignored); release and tap ⇧ again: wheel opens |
| A3 | T11 switch | With the Convert wheel open, tap ⌘ | Tools wheel replaces it in place (glass morph); no highlight carried over; one haptic |
| A4 | T11 switch back | Tap ⇧ again | Convert wheel returns; highlight cleared |
| A5 | T10 re-tap | With a wheel open, tap the same key again | Wheel closes; the drag continues normally |
| A6 | T12 refuse | Drag a folder, tap ⇧ | Convert wheel shows its empty-state pill; tap ⌘: the current wheel stays, shakes, and says why for about a second |
| A7 | T13 unbound chord | With a wheel open, press ⇧⌘ together | Nothing changes |
| A8 | T15–T16 drop | Drop on a slice | Wheel closes; the HUD appears near the pointer at once |
| A9 | Hub drop | Drop on the centre of the wheel | Nothing is converted; the file goes back to where it came from (snap back) |
| A10 | T14 release outside | Open a wheel, move off it, release over the desktop | Wheel closes at once; nothing converted; Finder handles the drop as usual |
| A11 | T17 Esc | Open a wheel, press Esc while still dragging | Wheel closes; the drag continues; Esc reaches other apps again once the wheel is gone |
| A12 | T17 Esc after release | Open a wheel, release over it slowly, press Esc during the release | Wheel closes; nothing converted |
| A13 | T18 Space change | Open a wheel, switch Space with a three-finger swipe or ⌃→ while dragging | Wheel hides; no stray panel left on either Space |
| A14 | T19 new keys | Settings › General: set Convert to ⌘; drag and tap ⌘ | Convert opens with ⌘ and ⇧ now opens Tools (the two swapped); the menu's key line shows the new keys. Set Actions to ⌥: ⌃ opens nothing, ⌥ opens Actions |
| A15 | Pause | Status menu › Pause Zivlet; drag and tap ⇧ | No wheel; the menu bar symbol shows paused; Resume brings it back |

## B. Accessibility and feedback

| # | Check | Steps | Expected |
|---|---|---|---|
| B1 | Reduce Motion | System Settings › Accessibility › Display › Reduce motion on; repeat A1, A3 | Wheel fades in; the switch is a short fade (no morph, no scale) |
| B2 | Reduce Transparency | Reduce transparency on; repeat A1 | Solid wheel even when Settings says Glass |
| B3 | Increase Contrast | Increase contrast on; repeat A1 | Solid wheel |
| B4 | Sound off | Settings › General: tick off; move across slices | No tick; haptics still on |
| B5 | Haptics off | Haptics off; move across slices | No haptics; tick still on |
| B6 | System UI sounds off | System Settings › Sound › Play user interface sound effects off | No tick whatever Zivlet's setting says |

## C. Sources, Spaces and displays (P1-64)

For each source: drag one file, tap ⇧, drop on a slice, and check the result appears beside the original (or in the
fallback folder with the card saying so).

| # | Source or setup | Expected |
|---|---|---|
| C1 | Finder window | pass as A1–A8 |
| C2 | Desktop | pass; the first save may ask for Desktop access once |
| C3 | Safari (drag an image from a page) | Wheel opens only if the drag carries a file; otherwise nothing (no wheel, no error) |
| C4 | Chrome (same) | as C3 |
| C5 | Photos (drag a photo out) | Phase 2: promise sources are not offered yet; record what happens (no crash, no stuck wheel) |
| C6 | Mail attachment | Phase 2, as C5 |
| C7 | VS Code (drag a file from the explorer) | pass |
| C8 | Dropover (or another shelf app) running | Both apps behave; Zivlet's wheel still opens on the key tap |
| C9 | Full-screen app on its own Space | Wheel opens above the full-screen app; HUD visible there |
| C10 | Two displays, wheel near the shared edge | Wheel stays whole on the display under the pointer |
| C11 | Two displays with different refresh rates (60 + 120 Hz) | Wheel opens within a frame on both |
| C12 | Stage Manager on | pass, or record what differs |
| C13 | External display only (lid closed) | pass |

## D. Cancel paths during a conversion

| # | Check | Steps | Expected |
|---|---|---|---|
| D1 | Cancel from the HUD | Convert a long video, press Cancel | HUD says Cancelled; no output and no `.zivlet-*` staging file left |
| D2 | Cancel from the menu | Same, cancel from the status menu's batch row | as D1 |
| D3 | Quit while converting | Same, quit from the menu | Zivlet quits within about 2 s; no helper left in Activity Monitor |
| D4 | Two drops at once | Start two conversions quickly | Two HUD panels, the second 24 pt down-right of the first; each Cancel acts on its own batch |

## E. Onboarding practice (P1-47 support)

| # | Check | Expected |
|---|---|---|
| E1 | Practice page 2: drag the sample tile from the window, tap ⇧, drop on any slice | "That's it." and no file is converted |
| E2 | Practice page 2: tap ⌘ instead | The line names the wheel that opened and the key to use |
| E3 | Practice page 3: ⌘ then ⌃ | "Now try ⌃ for Actions.", then "That's it." |
| E4 | After Finish: the next three real drags | Key legend beside the wheel; gone from the fourth drag |

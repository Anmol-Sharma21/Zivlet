# QA checklist: the tool window

Owner rows for the tool window (P2-30) from [20](../20-implementation-plan-m7.md) §7 and
[20b](../20b-m7-tool-window.md). The window's state, its placement on a screen, the fields, the slider, the timecode
and the remembered options are covered by unit tests; every state on screen in the Debug app by `make tool-states`
(V11). These rows check what only a person, a keyboard, VoiceOver or a second display can show.

## Setup

- A build of Zivlet: `make app` (Debug), onboarding finished, the worker present in the bundle.
- At the top of the run, record the macOS build, the Mac model, the displays and the Zivlet commit.
- Use PDFs you made yourself, in your own words; a password you type here is only for the test file.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). No result is written until it is
  seen. A fail opens an issue.

## W. The window

| # | Check | Steps | Expected | Result | Status |
|---|---|---|---|---|---|
| TW1 | Where it opens | Drop a PDF on LOCK · UNLOCK on the main display, then on a second display; then drag to each screen edge (top left, top right, bottom left, bottom right) before dropping | The window opens where the wheel was, wholly on the display of the drop, never under the menu bar or the Dock, never cut by an edge | | open |
| TW2 | Keyboard only | Open Lock; Tab through every control; press Space on the eye button; Esc; open again, type matching passwords and press Return | Tab reaches each field, the eye button, the restrictions and the buttons in reading order; the eye shows and hides the text; Esc closes with nothing done; Return runs Lock only when it is enabled | | open |
| TW3 | VoiceOver (OS-M7-6) | With VoiceOver on, open Lock, then Unlock after one wrong password | VoiceOver reads the title, the file line, each field's label ("New password", "Confirm", "Password"), the reason Apply is off ("Passwords don't match") and "Wrong password" | | open |
| TW4 | Reduce Transparency, Increase Contrast | With the window open, turn each on and off in System Settings › Accessibility › Display | The finish changes at once to the solid surface (with a thin outline under Increase Contrast) and back; every text line stays readable (4.5:1 or more) | | open |
| TW5 | Focus (OS-M7-2) | In TextEdit, drag a PDF onto the wheel and drop on LOCK · UNLOCK; type without clicking | TextEdit stays the frontmost app (its menu bar stays); the typed letters go into the window's field, not into TextEdit; Esc returns typing to TextEdit | | open |
| TW6 | A full-screen app underneath | Put Safari in full screen; drag a PDF from a Finder window in Split View and drop on LOCK · UNLOCK | The window shows over the full-screen space, takes the typing, and closes without leaving the space | | open |
| TW7 | Paste and the editing keys | Copy a password you made for the test from TextEdit; open Unlock on a file locked with it; press ⌘V in the field, then ⌘A, ⌘X, ⌘V, ⌘Z and ⇧⌘Z; with the eye on, ⌘C | ⌘V pastes into the field; ⌘A selects it, ⌘X cuts, ⌘Z undoes and ⇧⌘Z redoes; ⌘C copies only while the field is revealed; nothing reaches TextEdit | | open |
| TW8 | It grows on screen | Drag to the bottom edge of the screen and drop a PDF on LOCK · UNLOCK; choose a restriction; on a locked file switch Unlock to Change | The window grows upward as needed; Cancel and Apply stay on screen, above the Dock | | open |

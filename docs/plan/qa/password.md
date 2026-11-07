# QA checklist: passwords

Owner rows for the password sheet and its policy (P2-101, P2-102) from [20](../20-implementation-plan-m7.md) §7 and
[20c](../20c-m7-password-sheet.md). The sheet's states, the strength hint, the Unicode variants, the wiping of
`JobSecret` and the policy probes (logs, settings, records, names, children) are covered by unit tests
(`make password-policy`, V7); the sheet on screen by `make tool-states` (V11). Automation never calls the system's
password suggestion (D-M7-27) and never types a key, so these rows check what only a person can.

## Setup

- A build of Zivlet: `make app` (Debug), onboarding finished.
- At the top of the run, record the macOS build, the Mac model, the keyboard layouts and the Zivlet commit.
- Use PDFs you made yourself; a password you type here is only for the test file. Never write a real password into
  a result.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). No result is written until it is
  seen. A fail opens an issue.

## P. The sheet and the policy

| # | Check | Steps | Expected | Result | Status |
|---|---|---|---|---|---|
| PW1 | Suggest and Copy (OS-M7-4) | Open Lock; press Suggest; then restrict printing and press "Copy owner password"; paste once into TextEdit; open a clipboard history app that honours concealed items | Suggest fills both fields with the same strong password and shows it; strength reads "Strong"; the owner password pastes once; the history app does not list it | | open |
| PW2 | Secure Input | Open Lock and type into a field; while typing, check with a tool you trust that shows Secure Input (for example `ioreg -l -w 0 \| grep kCGSSessionSecureInputPID`) | Secure Input is on while a field has focus and off once the window closes; no other app sees the keystrokes | | open |
| PW3 | A Devanagari password | Lock a PDF with a password in Devanagari; open the result in Preview | The sheet warns "Preview on Mac can't open PDFs whose password uses non-English letters."; the card carries the same note; Preview indeed cannot open it, and the result is written down for the S-PDF-LOCK matrix (pdf-lock PL1) | | open |
| PW4 | A batch with one wrong file | Lock five PDFs with one password, then drop the five locked files on LOCK · UNLOCK with one of them locked with a different password | "Use the same password for all 5 files" is offered; four unlock; the card says "Unlocked 4 of 5 files" and "1 file not unlocked"; Retry asks only for that file | | open |
| PW5 | Change after a wrong current password | Drop a locked PDF on LOCK · UNLOCK; switch to Change; type a wrong current password, a new one and its confirmation; press Change; then type the right current password and the new one again | The second sheet is a Change sheet (Current, New and Confirm) that says "That password didn't work."; after the right one the card says "Password changed" and the file opens in Preview with the new password only | | open |
| PW6 | One sheet per file, each its own job | Drop two locked PDFs on LOCK · UNLOCK; turn "Use the same password for all 2 files" off; unlock the first, and switch the second's sheet to Change | The first file is written unlocked; the second keeps a password, the new one; the card names both results | | open |
| PW7 | VoiceOver and the owner password | With VoiceOver on, open Lock and turn Allow copying off; move to the owner password | VoiceOver reads "Owner password — shown once" and then the password itself, once; Printing reads as a group of three choices with the selected one | | open |
| PW8 | Reveal one field | Open Unlock on a locked PDF; switch to Change; press Suggest; then press the eye on Confirm | Suggest shows New password and Confirm only; Current password stays dots; each eye shows or hides its own field | | open |

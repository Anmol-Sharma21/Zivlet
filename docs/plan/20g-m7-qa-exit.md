# 20g — M7 Stream F: QA rows, the M7 exit runner, screenshots and the record

Part of [20-implementation-plan-m7](20-implementation-plan-m7.md). Conventions: index §6. Exit rows: index §7.
Decision: D-M7-26. Pattern: [18e](18e-m6-qa-exit.md) and `Scripts/m6-exit.sh`.

---

## Task F1 — QA rows for the owner

| Field | Value |
|---|---|
| Goal | New files in `docs/plan/qa/`, in the format of `qa/copy-text.md` (ID, steps, pass bar, status `open`): `tool-window.md` (TW1 opens at the wheel on each display and at each screen edge; TW2 keyboard only: Tab order, Esc, Return, the eye button by keyboard; TW3 VoiceOver reads the title, file line, each field's label, the disabled reason and "Wrong password"; TW4 Reduce Transparency and Increase Contrast switch at once; TW5 the drop source stays frontmost and typing goes to the field; TW6 full-screen app underneath), `password.md` (PW1 Suggest fills, Copy pastes once and is not offered by clipboard history apps that honour the concealed type; PW2 Secure Input on while typing (another app's key logger sees nothing; the owner checks with a tool they trust); PW3 a Devanagari password: the warning shows, the card says Preview can't open it, Preview indeed can't; PW4 batch of 5 with one wrong file), `pdf-lock.md` (PL1 the S-PDF-LOCK matrix of P2-192: Preview, Acrobat Reader, Chrome, Edge on Mac and Windows, iOS Files, an Android reader; ASCII passwords open everywhere; non-ASCII results written down; PL2 restrictions honoured in Preview and Acrobat (print, copy, edit); PL3 a form PDF from the owner's own files stays fillable after lock and unlock; PL4 Undo of lock and unlock), `read-qr.md` (QR1 a printed QR photographed with the Mac's camera app and saved, then dropped; QR2 a menu PDF with a link: Open shows the full URL and opens only on click; QR3 a non-web payload shows no Open) |
| Acceptance | Each file lists its rows with `open` status; `docs/plan/qa/README` (if present) or the index links them |
| Effort | S |

**Files:** create `docs/plan/qa/tool-window.md`, `password.md`, `pdf-lock.md`, `read-qr.md`.

Commit `docs(qa): tool window, password, PDF lock and Read QR rows for the owner`.

---

## Task F2 — `Scripts/m7-exit.sh` (D-M7-26)

| Field | Value |
|---|---|
| Goal | The M7 exit rows V1–V13 (index §7) in the `m6-exit.sh` pattern: one bash process per row with errexit on, logs in `build/m7-exit/<row>.log`, one line per row `pass` / `FAIL` / `skip`, exit 1 when any row failed or skipped, `--only`, `--list`; script-test seams `ZIVLET_M7_EXIT_LOGS`, `ZIVLET_M7_LOG` (log tool), `ZIVLET_M7_RELEASE_APP`, `ZIVLET_M7_BASE` (default `5107be7`). V4 maps `make timing`'s exit 3 to `skip` with the load printed. V5 runs `Vendor/verify-native.sh CQPDF` and the worker `otool -L` check. V12 scans `tccd` lines for `preflight=no` from Zivlet or its worker while V6–V11 ran. V13 hygiene (index §7) |
| Acceptance | `Scripts/tests/test-m7-exit.sh` as `test-m6-exit.sh`: `--list` prints 13 rows; `--only V13` on a temporary git repository with a commit lacking `Signed-off-by` fails; a commit adding `print(` in `Sources/` fails V13; a planted `SecItemAdd` fails V13; a stub `make timing` exiting 3 gives `V4 skip` and an overall exit 1 |
| Effort | M |

**Files:** create `Scripts/m7-exit.sh`, `Scripts/tests/test-m7-exit.sh`; `Makefile` (`m7-exit:`).

RED: `bash Scripts/tests/test-m7-exit.sh` → `Scripts/m7-exit.sh: No such file`. Commit `test(scripts): the M7 exit
runner`.

---

## Task F3 — Demos and screenshots of the new UI

All demos are DEBUG paths of the Debug app (as M5/M6), read only files they create in their own temporary folders,
never open a panel or alert, and quit the app they launched. Passwords for demos come from a 0600 file in the demo's
temporary folder named by a DEBUG launch argument (`-ZivletDemoSecrets <file>`), read once and deleted by the demo;
**no password is ever in argv or the environment**, demos included. Captures crop each window with `screencapture -x -R`
from the frame line the app logs, as `demo-text-states.sh` and `demo-box-states.sh` do (Liquid Glass only shows in a
real screen capture; the terminal that runs those demos already holds the permission they use, so no new prompt is
expected; if one appears, the run stops and says so); they run only with the screen awake
(`ioreg … CGSSessionScreenIsLocked`), else print `skipped: screen locked`. A capture that caught a blank surface
is rerun once before it counts as a defect.

| Field | Value |
|---|---|
| Goal | `Scripts/demo-tool-states.sh` (`make tool-states`): into `build/tool-states/`: the tool window shell with a disabled reason; Lock empty; Lock typed with strength "Strong"; Lock mismatch (reason shown); Lock with restrictions and the owner password shown once; Lock non-ASCII warning; Unlock empty; Unlock **wrong password** (after one wrong attempt, outline red, message line); Unlock owner-needed; Change password; the retry sheet with two names; Read QR results (two codes, one web link with Open); the lock and unlock result cards near the drop and at the notch; each in glass, Reduce Transparency and Increase Contrast; contrast of each text line over its surface computed with `Scripts/png-luminance.swift` (≥ 4.5:1). `Scripts/demo-lock.sh` (`make lock-demo`): a PDF the demo draws (our own words) → Lock (DEBUG secrets file) → `X Locked.pdf`; → Unlock → `X Unlocked.pdf`; → Change → new password works, old does not; each output checked with PDFKit by a small Swift checker run with the passwords on **stdin**. `Scripts/demo-qr.sh` (`make qr-demo`): two images and a PDF drawn with Core Image QR and Code 128 codes → the results window → payloads equal. `Scripts/demo-locked-input.sh` (`make locked-input-demo`): Copy Text on a locked PDF → the prompt (answered from the DEBUG secrets file) → clipboard text (private pasteboard, as M6's demo) within 1 % CER |
| Acceptance | Each script's test in `Scripts/tests/` with a stub app and stub log tool (as the M6 demo tests): screen locked → `skipped: screen locked`, exit 0 with nothing captured; a missing PNG → exit 1; the secrets file is deleted after the run and never passed as a value on any command line (the test greps the stub's argv) |
| Effort | M |

**Files:** create `Scripts/demo-tool-states.sh`, `demo-lock.sh`, `demo-qr.sh`, `demo-locked-input.sh`, their tests,
`App/ToolShots.swift`, `App/ProtectDemo.swift` (DEBUG only), `Makefile` targets.

RED: each script test fails on the missing script. Commits `test(app): every tool window and password state on
screen`, `test(app): lock, unlock and change through the drop path`, `test(app): Read QR through the drop path`,
`test(app): a locked PDF's password asked for by Copy Text`.

---

## Task F4 — The exit run and the record

| Field | Value |
|---|---|
| Goal | In a fresh `git clone` of the local repository at `m7`'s head, with `Vendor/out`, `Vendor/src` and `Vendor/downloads` copied in (so nothing existing is rebuilt; CQPDF comes from the cache made in C2), under `nice -n 10`: `make test lint coverage app release-check licence-gate script-test`, `make timing`, `Scripts/m5a-exit.sh`, `Scripts/m5b-exit.sh`, `Scripts/m6-exit.sh`, `Scripts/m7-exit.sh`, each once, loads printed before and after; each failure rerun once by name with both results kept. Then `docs/plan/21-m7-record.md` (the next free number): scope delivered per stream with commits; the gate table; the timing table with the load each row was judged at or "not judged"; coverage per module including `EnginePDF` and the shim; size before/after and the qpdf contribution vs 4.5 MB; qpdf build time; what the screenshots show and which were not looked at by a person; decisions taken; gaps still open (G-M7-*); owner steps (OS-M7-*) with status; a leak scan of `m6..m7` (signed off, no `Co-Authored-By`, no personal or scratch path, no names of other apps, no binary files, no downloaded PDFs) |
| Acceptance | The record exists, every row says pass, fail, skip or not run, and nothing is claimed that was not run |
| Effort | M |

**Files:** create `docs/plan/21-m7-record.md`.

Commit `docs: record M7`.

---

## Execution notes (stream F, done on `m7`)

Commits: F1 `5ab5ac3`; F2 `5138cf0` and `a7ad58c`; F3 `9dcf587`, the island card fix `b9b7af6` and the tool states
quit fix `ed6c756` (found by the exit run); F4 the record. What was run, the deviations (D-M7-53 to D-M7-59,
`make pdf-smoke` built here, captures by window number after a region capture took another app's window, rows that
quit every Zivlet not run while another was open) and what was not done are in [21](21-m7-record.md) §9; the exit run
in §3 and §4.

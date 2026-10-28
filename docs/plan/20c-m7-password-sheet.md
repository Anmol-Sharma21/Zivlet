# 20c — M7 Stream B: the password sheet (P2-101) and the password policy tests (P2-102)

Part of [20-implementation-plan-m7](20-implementation-plan-m7.md). Conventions: index §6. Decisions: D-M7-14,
D-M7-15, D-M7-27, D-M7-28. Prototype: index §3.2–§3.3. Gap audit: index §2.4–§2.5. Policy:
[design/17b](../design/17b-lock.md) §2 and §3 (shared by every family), [design/17a](../design/17a-pdf.md) §3.1–§3.2,
OWN-LK-1, OWN-PDF-1. Swift below is specification-grade and was not compiled.

Acceptance being built.
- **P2-101:** `SecureField` ×2 + an eye button, a strength hint, **Suggest** via `SecCreateSharedWebCredentialPassword`
  + Copy; Unlock's field shakes on a wrong password, with no attempt limit; NFC → NFD silent retry; batch "same password
  for all n" on by default, failures re-listed in a second sheet; per-family notes (the PDF non-ASCII warning in M7;
  ZIP and Office notes come with their rows); VoiceOver "Wrong password"; Return = Lock. FR-96 adds the footer
  "Zivlet can't recover forgotten passwords…" and Change (current + new + confirm). The [challenge] in FR-96: Copy
  writes with `.currentHostOnly` and the concealed/transient markers.
- **P2-102:** a test password never appears in an `os_log` capture, History JSON, crash-report fields, `UserDefaults`,
  or the argv or environment of any child; passwords are held as bytes and zeroed after use (best effort); the
  plaintext staging folder is 0700 and removed on cancel and at the next launch; a CI grep fails on any `--password `
  argv construction. The owner's brief adds: never written to disk, never in settings or diagnostics, passed to the
  worker over XPC only for the one job.

What the prototype showed (index §3.2): a password in an own allocation, sent inside a Codable request over a real XPC
session and zeroed on both sides afterwards, still leaves **two** copies in the app process's writable memory: the
`String` the text field produced, and one buffer inside XPC's message (freed by XPC, not zeroed; the copy is XPC's
own, since encoding from our buffer without a `Data` copy left the same count). Swift strings are immutable and XPC
does not zero its buffers, so P2-102's "zeroed" is honoured for Zivlet's own buffers only. The record must say so.

New strings (*new*, Zivlet's own unless quoted from 17a/17b): "Password", "Confirm", "Current password", "New
password", "Show password" / "Hide password" (eye button labels), "Weak", "Fair", "Strong", "Suggest", "Copy",
"Passwords don't match", "Use 127 bytes or fewer" (R6's limit), "That password didn't work." (17b §3.5), "Zivlet can't
recover forgotten passwords. Try the password again, or ask the person who sent the file." (17b §2.1), "Use the same
password for all 3 files", "Preview on Mac can't open PDFs whose password uses non-English letters." (17a §3.1),
"Change password…", "Restrictions", "These didn't open:" (the second sheet), "Wrong password" (VoiceOver).

---

## Task B1 — `JobSecret`: a password in memory (D-M7-14)

| Field | Value |
|---|---|
| Goal | `JobSecret` in `ZivletCore` (Foundation only): a final class holding the bytes in one allocation of its own; `init(utf8 string: String)` and `init(bytes:)`; `withBytes(_:)`; `wipe()` = `memset_s` over the buffer; `deinit` wipes then frees; `description`, `debugDescription` and `customMirror` show `<password>` (no bytes, no length); not `Equatable` by value (two secrets compare by identity), not `Hashable`, and **not `Codable`**: no settings, history, job-record or diagnostics encoder can take one, and a struct holding one cannot be synthesised as `Codable` by accident. Its bytes are reachable only through `package func withBytes(_:)` (SwiftPM `package` access), which `ZivletIPC`'s internal `WireSecret` uses to put them on the worker wire as `Data` and to rebuild a `JobSecret` on the other side. `JobSecrets` = the passwords one job needs: `input` (opens the file), `newUser`, `owner` (each optional), with a `wipeAll()` |
| Acceptance | `String(describing:)`, `String(reflecting:)`, `dump` and string interpolation of a secret and of a struct holding one contain neither the bytes nor the test password; after `wipe()` the buffer reads all zero (through a test seam that reads the buffer, never after free); `JobSecret.self is any Encodable.Type` is false; a `WireSecret` round trip (JSON, as the loopback does) gives the same bytes; a 128-byte secret is accepted here (the 127-byte rule is the sheet's and the validator's, B2/E3) |
| Effort | S |

**Files:** create `Sources/ZivletCore/Secrets/JobSecret.swift`, `JobSecrets.swift`,
`Tests/ZivletCoreTests/JobSecretTests.swift`; create `Sources/ZivletIPC/WireSecret.swift`,
`Tests/ZivletIPCTests/WireSecretTests.swift`. The prototype (index §3.2) sent exactly this shape (bytes as `Data`)
through a real `XPCSession`.

RED: `cannot find 'JobSecret' in scope`. Commit `feat(core): a password type that wipes itself and is never stored`.

---

## Task B2 — `PasswordRules`: checks that need no UI

| Field | Value |
|---|---|
| Goal | Pure functions in `ZivletCore/Secrets/PasswordRules.swift`: `strength(_:) -> Strength` (`.weak` < 8 characters or one class; `.fair` 8–11 or two classes; `.strong` ≥ 12 and ≥ 3 classes, or ≥ 16 of any; classes: lower, upper, digit, other; computed locally, nothing sent); `fitsPDF(_:) -> Bool` (UTF-8 ≤ 127 bytes, R6's limit); `isASCII(_:)` (drives OWN-PDF-1's warning); `variants(_:) -> [String]` (as typed, then NFC, then NFD, without duplicates, for the silent retry); `matches(_:_:)` for Confirm |
| Acceptance | Table tests: "abc" weak; "correct horse" fair; "Gx7!pLq2#vR9" strong; 16 lower-case letters strong; a 127-byte Devanagari string fits, 128 does not; `variants("café")` is `["café" (as typed), NFC, NFD]` minus duplicates (an NFC-typed input gives two entries); ASCII detection for "पासवर्ड-2026" false, "open sesame" true |
| Effort | S |

**Files:** create `Sources/ZivletCore/Secrets/PasswordRules.swift`, `Tests/ZivletCoreTests/PasswordRulesTests.swift`.

RED: `cannot find 'PasswordRules' in scope`. Commit `feat(core): password strength, length and Unicode variants`.

---

## Task B3 — `PasswordSheetModel`: the sheet's states (pure)

| Field | Value |
|---|---|
| Goal | Immutable `PasswordSheetModel` in `ZivletUI/Password/`: `mode` (`.lock`, `.unlock`, `.change`, `.ownerNeeded`), `fileLine`, `count` (n files), `sameForAll` (default `true` when n > 1), `revealed`, `strength`, `notes: [PasswordNote]` (`.nonASCIIPDF`, `.restrictionsNeedOwner`, later ZIP/Office notes), `failure` (`nil` or `.wrong(attempt: Int)` whose change drives one shake per wrong attempt; no limit, no delay), `retryList: [String]` (file names for the second sheet). `apply` is derived: Lock disabled with "Passwords don't match", "Use 127 bytes or fewer" or no reason when the two fields are empty (then the label is just disabled with reason "Type a password" *new*); Unlock enabled when the field is non-empty. Return triggers Apply (the default action, A2). Unlock has a "Change password…" switch that turns the same window into `.change` (FR-96, [challenge] in 17 §8.1: not a wheel slice). The model never holds the typed text: the view owns the `String` state and hands a `JobSecret` to `apply` |
| Acceptance | Transition tests: lock with mismatch → disabled with that reason; match → enabled "Lock"; non-ASCII → `.nonASCIIPDF` note shown, Apply still enabled (OWN-PDF-1 allows it); unlock wrong twice → `failure == .wrong(attempt: 2)` (two shakes); `sameForAll` default on for 3 files, off for 1; `retry(names:)` returns a model listing exactly those names; switching to change shows three fields; VoiceOver announcement text for a wrong attempt is "Wrong password" |
| Effort | M |

**Files:** create `Sources/ZivletUI/Password/PasswordSheetModel.swift`, `PasswordNote.swift`,
`Tests/ZivletUITests/PasswordSheetModelTests.swift`.

RED: `cannot find 'PasswordSheetModel' in scope`. Commit `feat(ui): the password sheet's states`.

---

## Task B4 — `PasswordSheetView` in the tool window

| Field | Value |
|---|---|
| Goal | SwiftUI content for A2's window: `SecureField`s (Password + Confirm; Current + New + Confirm in change; one field in unlock), each with an eye button (`eye` / `eye.slash`, labels "Show password" / "Hide password") that swaps the field for a `TextField` bound to the same state while held on; focus on the first field when shown (`@FocusState`, prototype §3.3); the strength word under the fields (lock and change only); **Suggest** (B5) fills both fields and reveals them, with **Copy** beside it; the footer line (17b §2.1 copy) in unlock and owner-needed modes; per-file notes as single lines with a symbol (`exclamationmark.triangle` for the non-ASCII note); the batch toggle "Use the same password for all n files"; a wrong attempt shakes the field 3 × 6 pt in 0.3 s (Reduce Motion: no shake, the field's outline turns red for 1 s) and posts the VoiceOver announcement. Copy writes to the general pasteboard with `.currentHostOnly` and the concealed and transient types (`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`), as 17b's [challenge] asks |
| Acceptance | View-model bindings tested through the model (B3); a shell test hosts the view in an off-screen `ToolWindow` and checks: the first responder is a secure field's editor after showing (as the prototype measured), Esc cancels, Return applies when enabled; the pasteboard fake receives the concealed and transient types and `.currentHostOnly`; accessibility labels exist for every control (`accessibilityChildren` walk) |
| Effort | M |

**Files:** create `Sources/ZivletUI/Password/PasswordSheetView.swift`, `PasswordFieldRow.swift`,
`SecretPasteboard.swift`, `Tests/ZivletUITests/PasswordSheetViewTests.swift`.

RED: `cannot find 'PasswordSheetView' in scope`. Commit `feat(ui): the password sheet in the tool window`.

---

## Task B5 — Suggest (D-M7-27)

| Field | Value |
|---|---|
| Goal | `PasswordSuggesting` protocol; `SystemPasswordSuggester` calls `SecCreateSharedWebCredentialPassword()` (macOS 11+; returns an `xxx-xxx-xxx-xxx` string; it generates, it does not read or write Keychain items) and returns a `JobSecret` plus the display string, or nil (the button then hides). Unit tests and every automated run use `FakeSuggester`; the real call is exercised only by the owner (OS-M7-4), because this session's hard limits keep automation away from anything Keychain-adjacent |
| Acceptance | With the fake: Suggest fills both fields equal, reveals them, strength `.strong`; nil → the button is hidden. A lint check (B7) allows `SecCreateSharedWebCredentialPassword` only in `SystemPasswordSuggester.swift` |
| Effort | S |

**Files:** create `Sources/ZivletUI/Password/PasswordSuggester.swift`, `Tests/ZivletUITests/PasswordSuggesterTests.swift`.

RED: `cannot find 'FakeSuggester' in scope`. Commit `feat(ui): Suggest a strong password`.

---

## Task B6 — `PasswordPrompting`: asking from the app

| Field | Value |
|---|---|
| Goal | `PasswordPrompter` (app side, behind a protocol for tests): `ask(_ request: PasswordRequest) async -> PasswordAnswer` where `PasswordRequest {mode, files, near: CGPoint?, notes}` and `PasswordAnswer` = `.cancelled` or `.secrets(JobSecrets, sameForAll: Bool)`. It opens A2's window (D-M7-15) at `near` (the wheel, the HUD card or the island) and resumes when Apply or Cancel is pressed. `retry(failed: [String])` opens the second sheet listing the failures; successes are never redone (17b §3.3). Secrets the prompter created are wiped when the batch that received them ends (the batch owns them, E9) |
| Acceptance | With a fake window: Apply resolves with secrets; Cancel resolves `.cancelled`; a second `ask` while one is open waits for the first (one window, A5's rule); `retry` lists exactly the failed names |
| Effort | S |

**Files:** create `Sources/ZivletUI/Password/PasswordPrompter.swift`, `App/PasswordWiring.swift`,
`Tests/ZivletUITests/PasswordPrompterTests.swift`.

RED: `cannot find 'PasswordPrompter' in scope`. Commit `feat(ui): ask for a password from the wheel, the HUD or the
island`.

---

## Task B7 — P2-102: the policy tests and the CI grep

The tests run a real lock, unlock and change through the loopback worker (E4–E7 must exist; B7's grep and the
UserDefaults and diagnostics parts can land first and grow). The password is a random string made per run
(`"zv-test-" + UUID`), so a match cannot be a coincidence.

| Field | Value |
|---|---|
| Goal | `PasswordPolicyTests` (in `ZivletRuntimeTests`, with the loopback worker and `EnginePDF` through `WorkerTestSupport`): after lock + unlock + change + a wrong attempt + a cancelled job, the password's bytes appear in **none** of: (1) `OSLogStore(scope: .currentProcessIdentifier)` entries since the test began, every subsystem; (2) the `UserDefaults` suite used by the app (a test suite name) and `ToolOptionsStore`; (3) the job-record folder (`JobRecordStore`), the undo log and history files (whatever `UndoLog`/`UndoHistory` write; History proper is P2-145, G-M6-3), and the diagnostics text (`Diagnostics.render` with live sources); (4) the staging folder's file names and the published output's file name; (5) the argv and environment of every child spawned during the run (`ExecutionContext.spawned` recorder: for PDF jobs the list must be **empty**, D-M7-16); (6) the `JobError`/`TextError` values and their copy. Also: the staging folder is 0700 while a job runs; a cancelled unlock leaves no staging folder; `OrphanReaper` removes a leftover `.zivlet-<job>` folder at the next launch (existing behaviour, now pinned for an unlock job). `Scripts/check-secrets.sh` (run by `make lint`): fails on `"--password"` or `password=` inside an argv-building expression in `Sources/`, `App/`, `Worker/` (pattern list with a self-test), on any Keychain item API (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`, `kSecClass`) anywhere in `Sources/`, `App/`, `Worker/`, on `SecCreateSharedWebCredentialPassword` outside the suggester file, and on a `Logger`/`os_log` line that interpolates an identifier named `password`, `secret`, `passphrase` or `JobSecret` |
| Acceptance | Each probe is seen to catch a planted leak before it is trusted: a test-only `logger.error("\(password, privacy: .public)")` → (1) fails; writing the secret's bytes into a test defaults key → (2) fails; an argv with `--password=x` in a test child → (5) fails; each grep pattern has a positive and a negative sample in `Scripts/tests/test-check-secrets.sh` |
| Effort | M |

**Files:** create `Tests/ZivletRuntimeTests/PasswordPolicyTests.swift`, `Tests/WorkerTestSupport/LeakProbe.swift`,
`Scripts/check-secrets.sh`, `Scripts/tests/test-check-secrets.sh`; `Makefile` (`lint` runs `check-secrets.sh`).

RED: `cannot find 'LeakProbe' in scope`; then each planted-leak run recorded. Commits `test(runtime): a password
leaves no trace in logs, settings, records, names or children`, `ci(scripts): refuse password argv, Keychain calls and
logged secrets`.

---

## Decisions of this stream (copied to index §4)

| ID | Decision |
|---|---|
| D-M7-14 | Passwords are `JobSecret`s: own allocation, wiped with `memset_s` on `wipe()` and in `deinit`, redacted in every description, not `Codable` (only `ZivletIPC`'s `WireSecret` puts the bytes on the worker wire). They travel only inside the requests of their job (never in `JobRequest`, `ExecutionPlan`, `StagedOutput`, job records, undo, settings or diagnostics), are held by the batch for the job's life including one crash retry, then wiped. The typed `String` and XPC's own message buffer cannot be zeroed from Swift (prototype §3.2); the record says so |
| D-M7-27 | Suggest calls `SecCreateSharedWebCredentialPassword` behind a protocol; automation uses a fake; the owner checks the real button (OS-M7-4) |
| D-M7-28 | The strength hint is local (length and character classes), three words, nothing sent anywhere |

---

## Execution notes (stream B, done on `m7`)

Facts for the record (F4). Commits: B1 `0a4d6e2`, B2 `c93e2cb`, B3 `1b95579`, B4 `13d9a65`, B5 `6814ef1`, B6
`73f6b60`, then two fixes from the captures (`e4f62ed`, `a8f69f7`), B7 `f0f3cf4` (the grep) and `2b68988` (the probes
and policy tests), and `3a39e3a` (a policy test made safe in the full run). Every task's test was run and seen to fail
first (a missing type or, for the grep, a missing script), with one exception: B4's view tests were written first, but
the first build failed on an actor error in the new code, so the missing-type failure was then seen by setting the new
files aside and building again. `PasswordSettingsPolicyTests` was written after `LeakProbe` existed.

**Baseline.** `make test` on `4eedbf6`: 2187 tests in 22 bundles, all passing, load about 12–17.

**Deviations from the tasks above:**

- **B1.** `JobSecret` also has `isEmpty` and `isWiped`; `JobSecrets.all` lists each secret once when one object fills
  two roles. `WireSecret`'s JSON is base64 of the bytes: that is a wire form, not protection.
- **B2.** Strength counts characters (grapheme clusters), so 16 Devanagari letters are strong; Devanagari letters have
  no case and count as "other". Confirm matches canonically equal text (the unlock retries both forms anyway).
- **B3.** The model keeps facts about the typed text (`PasswordFacts`: has text, matches, fits, ASCII, strength), never
  the text. New strings: "Type the current password" (Change with an empty Current field), "This PDF has restrictions.
  Type its owner password to remove them." (the owner-needed note), "Password strength: Strong" (VoiceOver). The
  second sheet has no "Change password…" switch, and Change names its three fields above them (both seen in the
  captures, `a8f69f7`).
- **B4.** `PasswordSheetState` (an `@Observable` class) owns the typed text and hands `JobSecrets` over on Apply,
  emptying the fields; a wrong attempt also empties the field. The eye button toggles (it does not need holding).
  Return inside a text field runs Apply through a new `toolWindowSubmit` environment value of the tool window (the
  field takes Return before the window's default button). The `accessibilityChildren` walk was tried and dropped: in
  the test process SwiftUI exposed no accessibility tree at all (no element, not even the window's), so the labels are
  checked through `PasswordSheetView.controlLabels`, which uses the same strings as the view. Shell tests that need a
  key window (first responder, Esc, Return, the size check) skip while the screen is locked, like G-M7-14.
- **B5.** `PasswordSuggesting.suggest()` returns the text, not a `JobSecret` plus text: the fields hold the text and
  Apply makes the secret, so a second copy would be unused. `FakeSuggester` is DEBUG-only and the Release scan refuses
  its name. A generator that returns nothing hides the button after that press (it is not probed in advance, which
  would make a password nobody asked for).
- **B6.** `PasswordRequest` has no `notes`: the M7 notes come from the mode and the typed text. `PasswordAnswer` gained
  `.unavailable` for another tool's open window (it is brought forward, A5's rule); earlier Read QR results give way.
  Nothing in the app asks for a password yet: `PasswordWiring` is built for stream E (E9). DEBUG
  `-ZivletPasswordStates <state>` shows nine states with made-up text and the fake generator.
- **Fix `e4f62ed` (stream A's window).** The first capture showed the tool window one point high: a secure field
  taking focus writes its text back inside SwiftUI's update, the window measured then and read zero. The window now
  keeps its size when nothing can be measured and measures again after the update; a test shows it through the
  prompter with a focused field.
- **B7, now.** `LeakProbe` lives in `TestSupport` (no dependencies), not `WorkerTestSupport`, so the settings tests can
  use it too. Planted leaks were caught by every probe: a `.public` log line, a defaults value, a file name and a
  file's contents, a running child's argv (`--password=<random token>`), and a spawn request's arguments and
  environment. **The kernel shows no process's environment on this macOS, not even a child's** (`ps -E` and
  `KERN_PROCARGS2` list none), so a child's environment is checked at its spawn request instead. The log probe reads
  only what the log keeps readable (`.public` values); `.private` values read back as `<private>`, which is why
  `check-secrets.sh` refuses logging a secret at any privacy level. The grep checks one line at a time (an
  interpolation on a later line of a multi-line log call is not seen).
- **B7, deferred to stream E** (no job carries a password before E4–E7): the policy run through real Lock, Unlock,
  Change, a wrong attempt and a cancelled job in the loopback worker; the job-record, undo and history folders; the
  staging and published names of a PDF job; the "no child for a PDF job" check (D-M7-16); 0700 and the reaper pinned
  for an unlock job (both are already tested for every job in `PrivateStagingTests`). The commit title of `2b68988`
  names records and children; records are not probed yet, and children are probed by the self-tests only.

**Memory (D-M7-14, G-M7-5), as measured by the tests:** our buffer reads all zeros after `wipe()`. Not measured here:
the typed `String`s, the `Data` of `WireSecret`, the encoder's and XPC's buffers (the prototype found one XPC copy).

**Seen in the Debug app** (screen awake, load 4–6): all nine states captured with `-ZivletPasswordStates` into the
session's scratch folder (not tracked): Lock empty (reason "Type a password", Suggest), mismatch ("Passwords don't
match", masked fields, Strong, Copy), suggested (revealed, both fields alike, Lock on), non-ASCII (the PDF note,
Lock on), Unlock after a wrong password ("That password didn't work.", the change switch, the footer), Unlock of three
files (the same-for-all checkbox), the second sheet (two names, no change switch), Change (three named fields) and
owner-needed (the restrictions note); plus the solid and Increase Contrast finishes. The frontmost app was the same
before and while the sheet showed (`lsappinfo front`); the sheet takes the keyboard, as D-M7-10 intends. This also
covers part of G-M7-13 (the disabled-reason state is now seen on screen).

**Not seen or not measured:** real typing, the shake and the Reduce Motion outline on screen (the captures are still
frames), VoiceOver's announcement and focus order (OS-M7-6), the real Suggest button (OS-M7-4), Copy on the real
pasteboard (tests use a fake; nothing was written to the owner's clipboard).

**Gates after stream B (`nice -n 10`; load 1m).** `make test` on `3a39e3a`: 2269 tests in 22 bundles (2187 at the
baseline), all passing, load about 5. The first full run on `2b68988` failed one new test at load 18
(`theDiagnosticsFromTheLiveLogCarryNoPassword`: other suites' log lines pushed its line out of the report's last 200
lines), fixed in `3a39e3a`. `make lint` (with `check-secrets.sh`), `make coverage` (every gated module ≥ 80 %; ZivletCore
98 %, ZivletIPC 100 %, ZivletUI 92 %, EngineVision 86 % the lowest), `make app`, `make release-check` (size OK),
`make licence-gate` (13 components) and `make script-test` (36 scripts) passed on `3a39e3a` at load 3–17, and again
inside the exit runners. The screen was awake throughout, so the key-window tests ran.

| Runner | Result |
|---|---|
| `Scripts/m5a-exit.sh` (load 3 → 2.6) | X1–X5 and X7 pass (X2: the app's drop 12.9 ms of 50, judged at load 2.78). X6 fails on idle CPU (`progress`, `indeterminate`, `pill-progress`, `fast-progress`, `pill-progress-solid` at 1.1–1.7 % over a 1 % limit): G-M5a-1, not worked on |
| `Scripts/m5b-exit.sh` (load 2.6 → 2.0) | Y1–Y9 pass |
| `Scripts/m6-exit.sh` (load 2.0 → 4.6) | Z1–Z11 pass |
| `Scripts/m7-exit.sh` | not yet written (stream F, F2) |

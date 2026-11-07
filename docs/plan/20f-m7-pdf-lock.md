# 20f — M7 Stream E: PDF lock, unlock and change password (P2-106) and encrypted inputs (P2-107)

Part of [20-implementation-plan-m7](20-implementation-plan-m7.md). Conventions: index §6. Decisions: D-M7-19 to
D-M7-26. Gap audit: index §2.8–§2.9. Design: [design/17a](../design/17a-pdf.md) §3.1–§3.2 and D-PDF-4/D-PDF-6,
[design/17b](../design/17b-lock.md) §2–§3 and §9, [design/17](../design/17-feature-roadmap.md) §8.1 (with its
[challenge]), OWN-LK-1, OWN-PDF-1, OWN-PDF-5, FR-92, FR-97, FR-101. Needs Streams B, C and D. Swift below is
specification-grade and was not compiled.

Acceptance being built.
- **P2-106:** qpdf R6 AESv3 through the library (05 says `qpdfjob` JSON; D-M7-16 uses the shim, so the password is
  never in argv either way); optional restrictions (print none/low/high, copy, edit) with a random 24-character owner
  password shown once; Unlock with the owner password, or with the user password only when the file grants all
  permissions or user = owner (qpdf reports which matched); restrictions-only files need the owner password; Change
  Password needs the owner password when restrictions exist; outputs `X Locked.pdf` / `X Unlocked.pdf`; verify
  `/Encrypt` R6; non-ASCII password warning + "check it opens on Mac" result; RC4/AES-128 never written; the S-PDF-LOCK
  matrix recorded (P2-192, owner).
- **P2-107:** one Unlock prompt per encrypted input per job, the password kept in memory for that job only; outputs
  keep protection except Unlock (as is, via preserve-encryption, which may be RC4; upgraded to AES-256 only when the
  owner password is known; never owner = user); permission bits honoured (OWN-PDF-5); public-key/LiveCycle →
  `unsupportedEncryption`. The brief: a locked PDF dropped on a conversion asks for its password via the sheet, then
  converts; each output opens in PDFKit with the right password and refuses the wrong one; unlock output has no
  encryption; forms stay live where the docs require it.
- **Wheel rules:** respect P2-100's caps and P2-114's later design: **one** `tools.protect` slot per family; CHANGE
  PASSWORD is a mode of the Unlock sheet, never a slice (17 §8.1 [challenge]); "k of n" uses the OWN-2 badge.

What exists for "a conversion" (read this session, G-M7-2): the convert wheel shows a PDF's **JPG** and **PNG**
targets today, because `ConversionService.unavailableTargets` works per target and images produce JPG/PNG; but no
engine handles a PDF source (`ImageEngine.handles` needs a raster or SVG source; P2-12 is not built), so such a drop
fails with `pairNotSupported`. E11 makes availability per pair, which hides them until P2-12. P2-107's "then converts"
therefore covers the M7 PDF tools that read pages (Copy Text, Read QR) and Lock/Change; the conversions follow with
P2-12 (OS-M7-8).

New strings (*new*, Zivlet's own, or quoted from 17a/17b): "LOCK · UNLOCK" (slice), "Lock PDF", "Unlock PDF",
"Change Password", "Locked", "Unlocked", "Password changed", "This file has restrictions. Enter the owner password to
remove them.", "Printing" (None / Low quality / Full), "Allow copying", "Allow editing", "Owner password — shown
once", "Restrictions are honoured by most apps but are not security." (17a §3.1), "This file uses certificate-based
or very old encryption Zivlet can't open." (17b §3.5), "Already locked: left as it is", "Locked with AES-256",
"Preview on this Mac can't open it with this password." (OWN-PDF-1 note on the card).

---

## Task E1 — The LOCK · UNLOCK slot (D-M7-19)

| Field | Value |
|---|---|
| Goal | `ToolID.protect` (raw value `protect`, the `tools.protect` slot of 17 §8.1), label `LOCK · UNLOCK`, symbol `lock`, `.editor`, `.multiAllowed`, suffix `Locked` (the namer picks `Unlocked` for unlock, E2), `accepts: [.pdf]` (Office and ZIP join with their rows). Applicability: PDF single `shrink, protect, stripMetadata, pdfSplit, pdfArrange, copyText, qrScan` (7) and PDF multi `pdfCombine, shrink, protect, stripMetadata, pdfSplit, copyText, qrScan` (7), the 17 §8.1 order with today's tools; both under 12. The label is fixed in M7; P2-114 later refines it from a header probe without moving the slot, so frame 1 never changes (FR-18) |
| Acceptance | `ToolCatalogTests`: the two PDF lists exactly as above; every other list unchanged; the cap lint (`make cap-lint`) prints PDF single 7 and multi 7 and passes; the mixed-family rule: PDF + PNG shows no `protect` (it accepts only PDF); a `WheelGeometry` label-fit test: `LOCK · UNLOCK` fits the 82 × 22 pt label frame at 7.5 pt (03a §2) |
| Effort | S |

**Files:** `Sources/ZivletCore/Catalog/ToolSpec.swift`, `ToolTable.swift`, `Tests/ZivletCoreTests/ToolCatalogTests.swift`,
`Tests/ZivletCoreTests/CatalogCapLintTests.swift`, `Tests/ZivletWheelCoreTests/SliceBuilderCapTests.swift`, the label-fit test beside the wheel's label tests.

RED: `type 'ToolID' has no member 'protect'`. Commit `feat(catalog): one LOCK · UNLOCK slot for PDFs`.

---

## Task E2 — The job: `JobOperation.protect` and its names

| Field | Value |
|---|---|
| Goal | `JobOperation.protect(ProtectSpec)` with `ProtectSpec {mode: .lock(PDFRestrictions?) / .unlock / .changePassword, keepRestrictions: Bool}`; **no password field** (D-M7-14). `JobRequest`'s initializer validates a `.protect` job by the tool catalog (source must be in `ToolID.protect`'s accepted formats) instead of the conversion catalog; `JobRequest.pair` for it is `pdf → pdf` (the engine key). `PDFRestrictions {printing: .none/.low/.full, copying: Bool, editing: Bool}`. Naming (D-PDF-6, OWN-3): lock and change → `X Locked.pdf`, unlock → `X Unlocked.pdf`; an input already named `X Locked.pdf` that is unlocked → `X Unlocked.pdf` (the suffix is replaced, not appended: `Report Locked.pdf` → `Report Unlocked.pdf`); the existing collision rule adds ` 2`, ` 3` |
| Acceptance | `JobRequestTests`: a `.protect` job on a PDF is valid; on a PNG → `.pairNotSupported(.png, .pdf)`; `OutputNamerTests` for the five names above; a JSON round trip of `JobRequest` with every mode contains no field named like a password |
| Effort | S |

**Files:** `Sources/ZivletCore/Jobs/JobRequest.swift`, create `Sources/ZivletCore/Jobs/ProtectSpec.swift`,
`Sources/ZivletCore/Naming/OutputNamer.swift`, tests in `ZivletCoreTests`.

RED: `type 'JobOperation' has no member 'protect'`. Commit `feat(core): a protect job and its output names`.

---

## Task E3 — Secrets on the wire, for one job (D-M7-14)

| Field | Value |
|---|---|
| Goal | `WorkerRequest.prepare`, `.execute`, `.verify` and `.recognizeText`/`.readCodes` gain `secrets: WireSecrets?` (nil for every other job; `WireSecrets` is `ZivletIPC`'s `Codable` form of a job's `JobSecrets`, made right before a request is sent and turned back into `JobSecrets` in the worker, redacted in every description, `Equatable` by bytes only for the round-trip tests); `.inspectPDFs([URL])` (no secrets) returns `[PDFPreflight]` for the wheel's mode decision (E9). `WorkerProtocol.version` bumped. `WorkerRequestValidator`: secrets only on `.protect` jobs and PDF inputs of text/code jobs; each password 1…127 UTF-8 bytes (R6), at most three per job (`input`, `newUser`, `owner`), else `.unsupportedInput(.badPassword)` with copy "Use a password of 127 bytes or fewer." `RemoteEngine` and `WorkerConnection` pass the job's secrets through; `JobPipeline` takes them from the batch (`BatchSecrets`, a per-job map held by the batch and wiped when the job ends, including after its one crash retry, D-M6 retry rule). On the wire the secrets are `WireSecret`s (B1), the only way their bytes leave a `JobSecret` |
| Acceptance | IPC round trip with secrets through the loopback (JSON) and through a real anonymous `XPCListener` in-process (the prototype's shape, `ZivletWorkerCoreTests`); `dump` of every request with secrets shows `<password>`; validator refuses 128 bytes, four secrets, secrets on a conversion job; after a job ends (success, failure, cancel, crash-retry-then-success) the batch's secret buffers read zero (test seam) |
| Effort | M |

**Files:** `Sources/ZivletIPC/WorkerMessages.swift`, `Envelope.swift`, `WorkerRequestValidator.swift`,
`Sources/ZivletRuntime/RemoteEngine.swift`, `WorkerConnection.swift`, `JobPipeline.swift`, `JobScheduler.swift`,
`XPCSessionFactory.swift`, create `Sources/ZivletRuntime/BatchSecrets.swift`; `Sources/ZivletEngineKit/Engine.swift`
(default-implemented `prepare/execute/verify(…, secrets:)` that call today's methods, so other engines are unchanged);
tests in `ZivletIPCTests`, `ZivletRuntimeTests`, `ZivletWorkerCoreTests`.

RED: `extra argument 'secrets' in call`. Commit `feat(ipc): a job's passwords travel with its own requests only`.

---

## Task E4 — Lock (D-M7-20)

| Field | Value |
|---|---|
| Goal | `PDFEngine` (in `EnginePDF`, hosted by the worker) handles `.protect(.lock)`: prepare = pre-flight (D1) + limits (D2), refuses an encrypted input with `.alreadyEncrypted` (the wheel would have chosen Unlock, E9); execute = shim `encryptR6` with the user password and either the same password as owner (no restrictions; 17a §3.1) or the owner password from `secrets.owner` (restrictions on: a random 24-character password the **app** made with `SecRandomCopyBytes` over an unambiguous alphabet, shown once in the sheet with Copy before Apply, never stored, D-M7-20); permissions from `PDFRestrictions` (print none/low/full; copy → extract + accessibility kept on; edit → modify, annotate, fill forms, assemble); metadata encrypted; verify = D3 `.locked(revision: 6, method: .aes256, ownerSeparate: restrictions != nil)` + PDFKit. RC4 and AES-128 are never written (the shim exposes only `encryptR6`; `check-secrets.sh` also fails on a call to the R2–R5 setters outside test helpers) |
| Acceptance | Through the loopback worker on fixtures: (1) lock without restrictions → `X Locked.pdf`; shim: R 6, AESv3, `matched == .both` for the password; PDFKit: locked, right password unlocks with `permissionsStatus == .owner`, wrong refused; (2) with restrictions (print low, no copy, no edit) → user password gives `.user` and `allowsCopying == false`, the owner password gives `.owner`; (3) a form PDF keeps `fieldCount` and `signatureFieldCount` and the field still takes a value in PDFKit after unlock with the user password (forms stay live, FR-107); (4) a Devanagari password locks, qpdf re-opens it, PDFKit cannot → the card note (OWN-PDF-1); (5) the sheet's non-ASCII warning appears before Apply (B3) |
| Effort | M |

**Files:** create `Sources/EnginePDF/PDFEngine.swift`, `PDFEngine+Lock.swift`, `Sources/ZivletUI/Password/OwnerPassword.swift`
(generator, alphabet without `0 O 1 l I`), tests `Tests/EnginePDFTests/LockTests.swift`,
`Tests/ZivletUITests/OwnerPasswordTests.swift`.

RED: `cannot find 'PDFEngine' in scope`. Commit `feat(pdf): lock PDFs with AES-256 and optional restrictions`.

---

## Task E5 — Unlock and its rule (D-M7-21)

| Field | Value |
|---|---|
| Goal | `.protect(.unlock)`: open with `secrets.input`, trying `PasswordRules.variants` (as typed, NFC, NFD) silently; none matches → `.wrongPassword` ("That password didn't work."). If `matched` includes `.owner`, or the file grants every permission (`permissions == .all`), write with `decrypt`; otherwise refuse with `.ownerPasswordNeeded` ("This file has restrictions. Enter the owner password to remove them."), which the app turns into the sheet's `.ownerNeeded` mode (B3). A restrictions-only file (opens without a password) always needs the owner password. `.publicKey`/`.unknown` encryption → `.unsupportedEncryption` (17b §3.5 copy). Verify = D3 `.unlocked` + PDFKit `isEncrypted == false` + forms kept |
| Acceptance | Fixtures: user = owner (R6, shim) unlocks with that password; user ≠ owner with restrictions: the user password → `.ownerPasswordNeeded`, nothing written, staging removed; the owner password → unlocked; user ≠ owner with all permissions granted → the user password unlocks (the rule's second branch); restrictions-only CoreGraphics file → the empty password is not enough, owner password unlocks; RC4-40 and AES-128 legacy files unlock with their owner password; an NFD-typed "café-2026" unlocks a file locked with NFC; a `/Adobe.PubSec` file → `.unsupportedEncryption`; no attempt counter exists (ten wrong attempts in a row each answer `.wrongPassword`, the eleventh right one unlocks) |
| Effort | M |

**Files:** create `Sources/EnginePDF/PDFEngine+Unlock.swift`, `Tests/EnginePDFTests/UnlockTests.swift`;
`Sources/ZivletCore/Jobs/JobError.swift` (`wrongPassword`, `ownerPasswordNeeded`, `unsupportedEncryption`,
`alreadyEncrypted`, with copy in `JobErrorCopy`).

RED: `type 'JobError' has no member 'ownerPasswordNeeded'`. Commit `feat(pdf): unlock only with a password that may
remove the restrictions`.

---

## Task E6 — Change password (D-M7-22)

| Field | Value |
|---|---|
| Goal | `.protect(.changePassword)`: open with `secrets.input` (the current password); if the file has restrictions and `matched` lacks `.owner` → `.ownerPasswordNeeded`; else write `encryptR6` with `secrets.newUser` and: the same owner password when the typed current password was the owner one and restrictions exist (`keepRestrictions == true`, the same permission bits), or owner = new user password when the file had none. Output `X Locked.pdf` |
| Acceptance | Old user password no longer opens the output; the new one does; restrictions and the owner password survive a change on a restricted file; a change on an RC4-40 input writes R6 AESv3 (upgrade, since the owner password is known); verify passes (D3) |
| Effort | S |

**Files:** create `Sources/EnginePDF/PDFEngine+Change.swift`, `Tests/EnginePDFTests/ChangePasswordTests.swift`.

RED: change test fails with `.internalInvariant("mode not handled")`. Commit `feat(pdf): change a PDF's password`.

---

## Task E7 — Batches (17b §3.3)

| Field | Value |
|---|---|
| Goal | One sheet per drop. With "Use the same password for all n files" on (default), one secret set serves every job of the batch; Unlock tries it on each file; files answering `.wrongPassword` are collected and offered again in a second sheet that lists them (`PasswordPrompter.retry`), and successes are not redone. With the toggle off, the sheet asks per file in turn (the file line names it). Lock of n files writes n outputs |
| Acceptance | Batch tests with a fake prompter and the loopback worker: 3 locked files, the password right for 2 → 2 `Unlocked` outputs and a retry sheet naming the third; its right password → the third unlocked, the first two untouched; toggle off → three prompts in drop order; cancel on the retry sheet → 2 outputs and the card "1 file not unlocked" |
| Effort | M |

**Files:** create `Sources/ZivletUI/Password/ProtectBatch.swift`, `Tests/ZivletUITests/ProtectBatchTests.swift`.

RED: `cannot find 'ProtectBatch' in scope`. Commit `feat(ui): one password for a batch, with the failures asked
again`.

---

## Task E8 — Results on the card and the island

| Field | Value |
|---|---|
| Goal | The result card (near the drop or at the notch) says "Locked with AES-256" / "Unlocked" / "Password changed" as its line, with the usual Undo (moves the output to the Trash), Reveal, Open, Copy; the OWN-PDF-1 note line when verify returned `.macCannotOpen`; "Already locked: left as it is" for skipped inputs of a mixed drop (D-M7-19); errors use E5's copy and keep Retry (which reopens the sheet) |
| Acceptance | `ResultCardModel` and `NotchHUDBoard` tests for each line and note; Undo removes the output and leaves the input untouched |
| Effort | S |

**Files:** `Sources/ZivletUI/HUD/ResultCardModel.swift`, `Sources/ZivletUI/Notch/NotchHUDItem.swift` (lines only),
`Sources/ZivletRuntime/JobErrorCopy.swift`, tests in `ZivletUITests`.

RED: the card test expects "Locked with AES-256" and gets the conversion line. Commit `feat(ui): lock and unlock
results on the card and the island`.

---

## Task E9 — From the slice to the jobs (D-M7-19)

| Field | Value |
|---|---|
| Goal | `ProtectWiring` (app): a drop on LOCK · UNLOCK sends `.inspectPDFs` to the worker (no password; ≤ 30 ms per file is P2-114's later budget, not judged here), then: none encrypted → Lock sheet; all encrypted → Unlock sheet (with "Change password…"); mixed → Lock sheet for the plain files, the encrypted ones listed as "Already locked: left as it is" (OS-M7-3 asks the owner); a restrictions-only file in an Unlock drop → the `.ownerNeeded` sheet. Apply submits one `.protect` job per file with the batch's secrets (E3, E7). Cancel submits nothing. The sheet opens at the wheel's place (A2, D-M7-10) |
| Acceptance | Wiring tests with fake worker, prompter and submitter: each of the four drop kinds opens the right mode; Apply submits n jobs with one shared `JobSecrets` object; after the batch ends the secrets read zero; Cancel submits none; the `inspectPDFs` request carries no secret (dumped) |
| Effort | M |

**Files:** create `App/ProtectWiring.swift`, `Sources/ZivletUI/Password/ProtectPlanner.swift` (the pure decision),
`Tests/ZivletUITests/ProtectPlannerTests.swift`; `App/AppDelegate.swift` (route `.protect`).

RED: `cannot find 'ProtectPlanner' in scope`. Commit `feat(app): LOCK · UNLOCK asks for the right password and runs
the jobs`.

---

## Task E10 — Encrypted inputs in the M7 PDF tools (P2-107, D-M7-24)

| Field | Value |
|---|---|
| Goal | Copy Text and Read QR on a PDF that is locked: the worker's first answer `.pdfLocked` (Copy Text, existing) or `CodeError.pdfLocked` (A7) for that file makes the wiring ask once for that file (Unlock sheet, `near` = the working line's place, D-M7-15) and resubmit that file's job with `secrets.input`; one prompt per encrypted input per job; Cancel skips that file ("Needs a password" note). In the worker, `PDFTextSource` and `CodeReader` open with PDFKit and `unlock(withPassword:)` (trying the variants), then honour OWN-PDF-5: Copy Text needs the extract permission unless `permissionsStatus == .owner` (else the existing `.copyingNotAllowed` copy); Read QR renders pages, which needs no permission bit. Outputs of these tools are text and clipboard contents, so there is no PDF output to keep protected (P2-107's "keep protection" applies to PDF → PDF tools: Lock/Change in M7, Merge/Split/Compress later, D-M7-24). `.publicKey` → `unsupportedEncryption` copy. The text never leaves the worker except as today's result (D-M6-8); the password never reaches the app's log |
| Acceptance | Loopback tests: a locked two-page PDF (CoreGraphics AES-128, user password) → one prompt, then the text with CER 0.000 against the drawn words (M6's CER tool); wrong password → the sheet shakes (B3), right one → text; a user-password PDF without the copy permission → `.copyingNotAllowed`; the same with the owner password → text; Read QR on a locked PDF with a QR drawn on page 2 → one prompt, then the code; two locked PDFs in one drop → two prompts, one each |
| Effort | M |

**Files:** `Sources/EngineVision/PDFTextSource.swift`, `CodeReader.swift`, `Sources/ZivletRuntime/TextService.swift`,
`CodeService.swift`, `App/ToolWiring.swift` (or `App/CodeWiring.swift`), create
`Sources/ZivletUI/Password/LockedInputPrompting.swift`, tests in `EngineVisionTests`, `ZivletRuntimeTests`,
`ZivletUITests`.

RED: the locked-PDF Copy Text test fails with `.pdfLocked` and no prompt. Commit `feat(tools): Copy Text and Read QR
ask for a locked PDF's password`.

---

## Task E11 — Conversions offered per pair (G-M7-2)

| Field | Value |
|---|---|
| Goal | `CapabilitySnapshot` gains `availablePairs: Set<ConversionPair>?` (nil = today's behaviour, for old tests) filled by `ConversionService.availablePairs()`; `SliceBuilder`'s same-family and mixed-family paths keep a target only if every (or, for the badge, the counted) source pair is available. A single PDF then shows no convert slices and the existing empty state `.noInstalledConverter(.pdf)` until P2-12 lands. No other list changes (the image rows' pairs are all available) |
| Acceptance | `SliceBuilderTests`: a PDF alone → `.noInstalledConverter(.pdf)` (today `[.jpg, .png]`, the RED); a PNG alone → unchanged list; PNG + PDF mixed → only targets both can reach; the 161-pair matrix tests unchanged |
| Effort | S |

**Files:** `Sources/ZivletWheelCore/WheelContent.swift`, `SliceBuilder+Convert.swift`,
`Sources/ZivletRuntime/ConversionService.swift`, `App/AppDelegate.swift` (snapshot), tests in `ZivletWheelCoreTests`,
`ZivletRuntimeTests`.

RED: the PDF-alone test gets `[.convert(.jpg), .convert(.png)]`. Commit `fix(wheel): offer a conversion only when an
engine handles that pair`.

---

## Decisions of this stream (copied to index §4)

| ID | Decision |
|---|---|
| D-M7-19 | One `ToolID.protect` slot, label `LOCK · UNLOCK` in M7 (P2-114 refines it later without moving it); after the drop the worker's pre-flight picks the mode: none encrypted → Lock, all → Unlock (Change is a mode inside it), mixed → Lock for the plain files and the encrypted ones left as they are and listed (OS-M7-3) |
| D-M7-20 | Lock writes only R6 AES-256. Without restrictions the owner password is the user password (17a §3.1); with restrictions it is a random 24-character password made in the app, shown once with Copy, never stored |
| D-M7-21 | Unlock writes a decrypted file only when qpdf says the owner password matched or the file grants every permission; otherwise it asks for the owner password. No attempt limit, no delay, silent NFC/NFD retry |
| D-M7-22 | Change password keeps restrictions and the owner password when the owner password was typed; it upgrades legacy RC4/AES-128 inputs to R6 |
| D-M7-24 | In M7, P2-107 covers Copy Text and Read QR on locked PDFs (one prompt per file, password in that job only, permission bits honoured) and Lock/Change; conversions from PDF wait for P2-12, and E11 stops the wheel offering them meanwhile |
| D-M7-25 | Every test PDF is made at test time by our own code: CoreGraphics (plain, RC4-40 R3, AES-128 R4, restrictions-only, owner + permissions), PDFKit widgets (form and signature fields), and the shim (R6 with and without restrictions, non-ASCII passwords, structure and hostile cases). Nothing is downloaded |
| D-M7-26 | The M7 exit runner `Scripts/m7-exit.sh` follows `m6-exit.sh` (rows V1–V13, each in its own process, skip ≠ pass) |

---

## Execution notes (stream E on `m7`, 2026-11-07)

Commits: E1 `616a273`, E2 `b08e5e3`, E3 `1344f77`, E4 `a15b591`, E5 `524e463`, E6 `d5b437b`, E7 `ab91b89`, E8
`a3a23dc`, E9 `c81de3d`, E10 `bdaf472`, E11 `abe050a`, B7's deferred policy test `6f643dd`, and the build-order fix
`6d73e67` (G-M7-11) that the gate run needed. `make test` on `695c5cc`
was green before any of them: 2418 tests in 23 bundles (load 4.5–7.8).

**TDD.** Each task's test was written first and seen to fail, with these exceptions: E4's RED was a missing
`JobError.alreadyEncrypted` and plan note, not "cannot find PDFEngine" (stream C made the engine); `OwnerPasswordTests`
first failed on a test-code error, so the missing type was never seen alone; E10's text merge and E11's
`availablePairs()` were written beside their tests; the policy test (`6f643dd`) was written after the jobs existed, and
its probes are the ones stream B proved on planted leaks. E2's commit passed a lint call that checked nothing (an
unsplit file list in zsh); its two long lines and an indentation were fixed in E3's commit.

**Deviations from the tasks above** (decisions D-M7-46 to D-M7-52 in the index):

- **E1.** `protect` sits after `pdfCombine` in the catalog order. The label test measures every tool label with
  AppKit's 7.5 pt semibold and the petal's tracking, not a `WheelGeometry` call (there is none for labels).
- **E2.** The change mode's wire name is `change`, so no key of a request reads like a password. Either suffix is
  replaced (`Report Unlocked.pdf` locked is `Report Locked.pdf`). Every output is named through
  `OutputNamer.output(for:)`.
- **E3.** `WireSecrets` is a list of role entries rather than three fields, so "four secrets" and "a role twice" can be
  refused. Passwords on the wrong request are an internal invariant; only their shape is `.badPassword`. The worker's
  inspection is answered through an injected `PDFInspecting`, because `ZivletWorkerCore` must not link qpdf. The worker
  reports `pdf → pdf` among the PDF engine's routes, since it is not a catalog pair. **New:** `WorkerOnlyEngine`, the
  app's handle on an engine that exists only in the worker; with no worker a PDF tool job fails with
  `engineMissing(.pdf)` (closes G-M7-19). The real-XPC round trip covers `prepare`; the loopback covers the three
  steps. Worker protocol 7.
- **E4.** Verify also holds the output to its exact /P bits (`.permits`). The OWN-PDF-1 note is planned in prepare when
  the new password is not ASCII and withdrawn by execute when PDFKit opens the output after all. The restrictions
  section of the sheet was built in E9, where the sheet is used. `check-secrets.sh` refuses qpdf's R2–R5 setters in
  any source, C++ included.
- **E5.** Execute tries the Unicode forms again, because a plan carries no password. The owner-needed sheet's
  password is the one Unlock opens with. An unencrypted file in an Unlock job is rewritten without encryption, not
  refused.
- **E6.** Whether the owner password and restrictions stay is read from the file (it has restrictions and the owner
  password opened it), not from `keepRestrictions`. The kept owner password is the bytes as typed.
- **E7.** The batch logic is tested with a fake prompter and submitter in `ZivletUITests`, which cannot link the
  worker; `ConversionService.protect` is tested with the real PDF engine in the loopback worker. Each second sheet
  runs a batch of its own, with its own card. The "not unlocked" line counts wrong and owner-needed answers.
- **E8.** The mixed drop's locked files go through Lock and are refused with `alreadyEncrypted`, whose copy is now
  "Already locked: left as it is."; the card lists them as notes, not failures. *New* strings: the working titles
  "Locking", "Unlocking", "Changing password" and the partial title "Unlocked 2 of 3 files" (the mode's line, then
  the count).
- **E9.** The flow (`ProtectFlow`) lives in `ZivletUI` so it can be tested; the app's `ProtectWiring` only builds it
  and announces each batch to the presenters. "Change password…" is seen from the answer (a new password came back).
  Files the worker cannot read go along, so their job says why. DEBUG `-ZivletProtectDemo <folder>` runs lock,
  unlock and a wrong password through the flow with a scripted prompter; the password comes from a 0600 file it
  deletes once read.
- **E10.** A password that opens nothing comes back as `pdfLocked` again, so no new error crossed the wire. Each
  locked file runs its own job and its text takes its place in the drop's order. **Not done:** PDFKit cannot tell a
  certificate handler, so Copy Text and Read QR do not say "certificate-based" (they say locked), and G-M7-23's
  wording is unchanged.
- **E11.** With no pairs given, a PDF shows the whole catalog list (9 targets), not the two of G-M7-2: the app's real
  snapshot had already hidden the document targets. The test expects the catalog list.

**Seen in the Debug app** (screen awake, load 3–5). `-ZivletProtectDemo` locked, unlocked and refused a wrong password
on a two-page PDF made for the demo: the jobs ran in `ZivletWorker` ("Worker ready" in the log), "Report Locked.pdf"
and "Report Unlocked.pdf" were published beside the input, and the secret file was gone. This is the first PDF job
from the app to reach `PDFEngine` in the XPC worker; the watchdog's stop there was still not triggered (G-M7-22 stays
half). Captured by window number into the session's scratch folder (not tracked): the cards near the drop ("Locked
with AES-256", "Unlocked", "That password didn't work." with Retry), the island's lines for the same, and the sheets
`lockEmpty`, `lockRestricted`, `unlockWrong` and `ownerNeeded`. The first `lockRestricted` capture showed the Printing
control clipped at the sheet's right edge; it now sits on its own row (fixed in `c81de3d`). A first try captured the
whole screen, which takes other apps' windows; those files were deleted, and every capture since takes Zivlet's own
windows only.

**Not seen or not measured:** real typing in the sheet, Suggest, VoiceOver, the restrictions on another reader
(P2-192, owner row), a non-ASCII password through the app, a locked PDF through Copy Text or Read QR in the app (only
the loopback worker), and the island's working line for a protect batch on screen.

**Gates** (`nice -n 10`; load 1m; the screen was awake except where said).

| Gate | Result |
|---|---|
| `make test` on `6f643dd` | 2537 tests, 23 bundles, all pass (2418 at the baseline), load 4–13 |
| `make lint` | passes (with `check-secrets.sh`, now refusing qpdf's R2–R5 setters) |
| `make coverage` | 21 modules ≥ 80 %: EnginePDF 98 % (862/876), CZivletPDF 91 % (471/512), ZivletIPC 100 %, ZivletUI 92 %, ZivletRuntime 93 %, EngineVision 90 % the lowest |
| `make app` | passes after `6d73e67`; the Debug app verifies `codesign --verify --deep --strict` |
| `make release-check` | passes: Bundle OK, 57.0 MB installed, worker 8.4 MB, size OK |
| `make licence-gate` | 15 components, 58 crates |
| `make script-test` | passes |
| `Scripts/m5a-exit.sh` (load 4.6 → 3.1) | X1–X5 and X7 pass; X2 judged at load 3.00, every budget met. X6 fails on idle CPU (G-M5a-1, not worked on): `indeterminate`, `pill-progress`, `fast-progress` and `pill-progress-solid` over their 1 % (2.1 % the most) |
| `Scripts/m5b-exit.sh` (load 4.2 → 3.4) | Y1–Y9 pass, Y3 with X2 judged, Y8 passed |
| `Scripts/m6-exit.sh` (load 3.4 → 4.4) | Z1, Z2 and Z4–Z11 pass. **Z3 not judged (skip):** the Mac slept with its lid closed during its X2 wait (about ten hours by the clock), and X2 never found the load under 3.0; Z3's other rows (X3–X5, Y4, Y5, Y7) passed. X2 itself was judged twice in this run (X2, Y3) |
| `Scripts/m7-exit.sh` | not yet written (stream F, F2) |

The first gate run failed m5a X1 at `make app` (G-M7-11's race), which left an unsigned Debug app, so X2 and X3 of that
run failed too. `6d73e67` fixed the order; the runners above are the rerun. No fresh clone was run.

# 05 — Zivlet master task list (Phase 0 → Phase 3, backlog for 4/5)

Date: 2026-10-20. Status: working plan. Inputs: [00-decisions](../design/00-decisions.md), [10-tech-strategy](../design/10-tech-strategy.md) (where they conflict, the [challenge] notes win), [11](../design/11-media-engine.md)–[15](../design/15-strategy-challenge.md), [01-prd](01-prd.md).

Roadmap additions approved on 2026-10-21 (rows P2-100…, P3-100…, P4-100…, milestones M5a/M5b/M5c, and changes to
existing rows) are in §9; where §9.1 changes a row, §9.1 wins.

Clean-room rule for every task: behaviour and parameters come from our docs. No reference-app or Open-Tangerine code, assets, sounds, icons or screenshots are used.

---

## 1. Conventions

### 1.1 Columns

| Column | Meaning |
|---|---|
| ID | `P<phase>-<nn>`. Gaps in numbering are deliberate (groups). Backlog uses `B4-nn` / `B5-nn`. |
| Area | SwiftPM module (`Core` = `ZivletCore`, etc.), or `Repo`, `CI`, `Vendor`, `Release`, `App`, `QA`, `Spike`, `Owner` |
| Deps | Task IDs that must be done first |
| Size | **S** ≤ 1 day · **M** 2–4 days · **L** 5–10 days (one engineer, ESTIMATE) |
| Acceptance | Testable pass criteria. "Golden" = committed expected output under `Packages/ZivletKit/Tests/**/Golden/`. |
| Satisfies | FR IDs (§1.3), spike IDs (10 §13), decision IDs (O-n, D-n), challenge IDs (C-n) |

### 1.2 Flags

| Flag | Meaning |
|---|---|
| **[OWNER]** | Needs an owner action: Developer ID, domain, trademark, purchase, or a decision |
| **[HW]** | Needs specific hardware or OS images (M1 Air, 120 Hz MBP, 60 Hz external, Tart host with macOS 26.x VMs) |
| **[QA]** | Needs manual QA (real cross-app drags, usability, AirDrop) that CI cannot do |
| **[TDD]** | Pure logic: write the failing Swift Testing suite first, then implement. Default for every task in groups 0B, 0C, 1A. |

### 1.3 FR index (no FR numbering existed; defined here, anchored to source sections)

| FR | Requirement | Source |
|---|---|---|
| FR-01 | Drag + single-modifier tap opens the wheel; no permission prompts | 01-prd §5.1, 14 §1 |
| FR-02 | Mode switch, cancel (re-tap, hub, Esc), linger, never trap drops | 01-prd §5.3, C-8 |
| FR-03 | Wheel geometry, slot order, anchoring, screen clamping | 01-prd §5.5, 03a §2.1–2.3 |
| FR-04 | Hit-testing (exact + forgiving) and highlight states | 01-prd §5.6, 03a §2.4 |
| FR-05 | Empty states and status-pill copy | 01-prd §5.10, 03a §2.6 |
| FR-06 | Sound + haptic tick, one toggle, default on | 03a §2.7 |
| FR-07 | Conversion catalog: 275 pairs, wheel order, labels | 01-prd §6.1, 10 §4 |
| FR-08 | Only offer what works: capability-gated slices | 10 §8.8 |
| FR-09 | 27 tools: inputs, instant vs windowed, output suffixes | 01-prd §6.2, 10 §5 |
| FR-10 | 6 actions | 01-prd §6.3, 10 §6 |
| FR-11 | Output naming and collisions | 01-prd §5.9, 10 §8.5 |
| FR-12 | Atomic staging and publish, never overwrite, quarantine propagation | 10 §8.5, C-5 |
| FR-13 | Job queue, lanes, cancellation, crash isolation | 10 §8.1–8.3 |
| FR-14 | Progress HUD, result card, Undo | 01-prd §5.8 |
| FR-15 | Error taxonomy with user copy; never swallowed | 10 §8.4 |
| FR-16 | Multi-file, folders, mixed selections | 03a §2.6 |
| FR-17 | Output location (beside + Downloads fallback), promise drags | O-14 |
| FR-18 | Fidelity rules (ICC, orientation, 16-bit, animation, playable A/V) | 10 §4.2, C-9 |
| FR-19 | Security: input confinement, limits, helper integrity | 10 §8.9, C-4 |
| FR-20 | Diagnostics without telemetry | 10 §8.7 |
| FR-21 | Menu bar, Settings, onboarding, login item | 01-prd §6.4–6.6, 14 §3 |
| FR-22 | Accessibility and keyboard path | 01-prd §6.8, 03a §2.8 |
| FR-23 | Signing, notarization, Sparkle, GPL source obligations | 10 §10–11 |
| FR-24 | Performance budgets | 10 §8.11 |
| FR-25 | Extensibility: Services, App Intents, CLI | 14 §4 |
| FR-26 | Document, sheet and slide fidelity bars | 12, 10 §4.8–4.10 |
| FR-27 | Bundle size budget | 10 §9, O-3 |

### 1.4 Behaviour decisions this plan needs (defaults adopted; owner may override)

| ID | Question | Sources disagree | Default in this plan |
|---|---|---|---|
| D-1 | Multi-file conversion: intersection or union with "3 of 5" badges? | reference behaviour = intersection; union proposed as an improvement | **Intersection within one family**; **mixed families → badged union** if ≤ 12 slots, else "These files can't share a format" [critic3: aligned with 03a §2.6 and M1 Task 7 (06 index D5); confirm at P-W1] |
| D-2 | Re-tap of the active modifier | reference behaviour = no-op; 14 §1.3 and 10 §12 Phase 1 = close | **Close** (zero-permission cancel). Add to the O-16 list. |
| D-3 | Modifier already held when the drag starts | reference behaviour = opens wheel; 14 §1.3 = ignore (protects ⌘-move drags) | **Ignore until re-pressed**; `TriggerConfig.honorsModifierHeldAtDragStart` exists, default false [critic3: name as in 02 §7.6 / M1; 02, 03a and M1 now default false] |
| D-4 | Tool output suffixes | 10 §5 vs native names | **Native names** ("Speed 2.0x", "<first> Images.pdf", "Metadata Edited/Removed") unless O-16 lists a change |
| D-5 | PDF → images folder name | 10 §8.5 `<base> Pages`; alternative `<base> <EXT> Pages` | **`<base> <EXT> Pages`** (avoids JPG/PNG collisions) |

### 1.5 Repository and tooling facts every task assumes

| Item | Value |
|---|---|
| Root | repository root (paths below are repo-relative) |
| Project | `project.yml` (XcodeGen 2.45, `/opt/homebrew/bin/xcodegen`) → `Zivlet.xcodeproj` (git-ignored, never committed) |
| Package | `Packages/ZivletKit` (all modules; `swift test` with Swift Testing, `import Testing`) |
| Toolchain | Swift 6.4, Xcode 27, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on every build command |
| Target | macOS 26.0 minimum, arm64 only (O-13), not sandboxed, hardened runtime |
| Bundle id | `app.zivlet.Zivlet` placeholder (O-10) in one xcconfig variable |
| Signing | Ad-hoc in Debug until the Developer ID exists (O-11) |
| Dev engines | Debug builds may use Homebrew `ffmpeg`/`ffprobe` from `/opt/homebrew/bin`; Release never does (10 §8.9) |
| Owner rules | Immutable value types; files 200–400 lines (800 max); functions < 50 lines; nesting ≤ 4; ≥ 80 % coverage on gated modules; conventional commits; typed errors; boundary validation |

---

## 2. Milestones

| Milestone | Definition | Tasks that must be done | Exit check |
|---|---|---|---|
| **M1** | Repo skeleton + all pure core logic green under `swift test` | P0-01…P0-07, P0-10…P0-20, P0-21…P0-28 | `make lint test` exits 0 on a clean clone; coverage gate ≥ 80 % on Core, Trigger, WheelCore, EngineMedia; CI green on `main`. [critic3] 06 covers this in two steps: Tasks 1–9, then the 06 §2.1 rows (P0-03, P0-07, P0-11, P0-13, P0-17…P0-20, P0-22, P0-26…P0-28) |
| **M2** | Trigger + wheel running in a dev app build | M1 + P0-40…P0-43; spikes P0-31, P0-32 started | Dev build: drag from Finder, tap ⇧/⌘/⌃, wheel appears at pointer with correct slices, highlight follows pointer, drop logs a `JobRequest`, hub drop snaps back; no TCC prompt |
| **M3** | First conversions end-to-end via Homebrew ffmpeg + ImageIO | M2 + P1-01…P1-15, P1-20…P1-24, P1-30, P1-31, P1-33 | Dev build converts jpg→png, heic→jpg, mov→mp4, wav→mp3, mp4→webm; output appears beside the original, selected in Finder, verified, no partial files on cancel |
| **M4** | Phase 1 complete (private alpha 0.1) | All P1 tasks | 153 pairs green on the matrix (WebM playable); tap→wheel p95 ≤ 16 ms at 120 Hz; no prompts other than TCC folder prompts; hostile media corpus crash-free; notarized DMG + Sparkle stable channel |
| M5 | Phase 2 complete (public beta 0.5) | All P2 tasks | 221 pairs, 19 tools, 6 actions green; gate-B bars met; worker isolates hostile PDF/ZIP crashes |
| M6 | Phase 3 complete (1.0 parity) | All P3 tasks | 275 pairs, 27 tools, 6 actions green nightly on a clean macOS 26.x VM; release checklist, real-drag QA and size gate pass |

Critical path to M3: P0-02 → P0-10 → P0-12 → P0-15 → P0-27 → P0-41 → P1-33, with the planner chain P0-17 → P1-01 → P1-02 → P1-05 → P1-23 → P1-31 running alongside it.

---

## 3. Phase 0 — Skeleton, pure core, spikes (about 3–4 weeks)

[critic3] The four phase estimates add up to 32–43 weeks (about 8–10 months). 10 §12 [challenge] and 01-prd §10 put full parity at 12–18 months for one engineer (O-18). Read these figures as effort floors, not a date plan.

### 3.1 Group 0A — Repository skeleton

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P0-01 | Repository bootstrap | Repo | — | S | `git init`; `.gitignore` covers `Zivlet.xcodeproj/`, `.build/`, `DerivedData/`, `*.xcuserstate`, `Vendor/out/`; `LICENSE` = GPL-3.0-or-later; `CONTRIBUTING.md` requires DCO `Signed-off-by`; README states the clean-room rule; `git check-ignore Zivlet.xcodeproj` succeeds | O-1, O-2 |
| P0-02 | ZivletKit package skeleton | Package | P0-01 | M | `Package.swift` declares `ZivletCore`, `ZivletTrigger`, `ZivletWheelCore` (pure) [critic3: 02 §4.1 split], `ZivletWheel`, `ZivletEngineKit`, `EngineMedia`, `EngineImage`, `ZivletRuntime`, `ZivletUI` with one test target each; `.macOS(.v26)` (tools-version 6.2) [critic3]; Swift 6 language mode; `ZivletWheel`/`ZivletUI` use `defaultIsolation(MainActor.self)`; `swift build` and `swift test` exit 0 with a placeholder `@Test` per target. Other modules are added in the phase that needs them. | 10 §7.2 |
| P0-03 | Module dependency gate | CI | P0-02 | S | `Scripts/check-imports.sh` fails when Core imports AppKit/SwiftUI/WebKit, an `Engine*` other than `EngineRender` imports AppKit, or Trigger/Wheel imports any `Engine*`; a planted violation in a temp copy makes it exit non-zero | 10 §7.2 rules |
| P0-04 | XcodeGen project | App | P0-02 | M | `project.yml` defines app target `Zivlet` (`LSUIElement`, links ZivletKit products), `Config/Base|Debug|Release.xcconfig`, `ZIVLET_BUNDLE_ID`, hardened runtime, ad-hoc Debug signing, entitlements per 10 §11.2; `xcodegen generate && xcodebuild -scheme Zivlet build` succeeds; app runs as a menu-bar agent with no Dock icon | 10 §7.1, O-10, O-11 |
| P0-05 | Dev entry points | Repo | P0-04 | S | `make test` (swift test + coverage), `make app` (xcodegen + xcodebuild), `make lint` (swift-format lint + P0-03); all exit 0 on a clean clone; documented in README | 10 §8.10 |
| P0-06 | Coverage gate | CI | P0-05 | S | `Scripts/coverage-gate.sh` reads `llvm-cov export` from `swift test --enable-code-coverage`; prints a per-module table; exits non-zero if any gated module is < 80 % lines | owner rule, 10 §8.10 |
| P0-07 | PR CI workflow | CI | P0-03, P0-05, P0-06 | M | `ci.yml` on PR runs `make lint test app` unsigned (`CODE_SIGNING_ALLOWED=NO`) and uploads test + coverage reports. Hosted `macos-26` ships Xcode 26.6, so if Swift 6.4/Xcode 27 is missing the job targets the self-hosted runner (P0-34) and the README records why. Green on `main`. | 10 §11.1, C-10 |

### 3.2 Group 0B — ZivletCore pure logic [TDD]

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P0-10 | Format registry | Core | P0-02 | M | `Format` covers the 45 inputs (incl. `gz`) plus output-only `html` = 46 [critic3: gz is input and output; 06 index D7]; `family`; display label = upper-case extension except `gz` → "GZIP"; `Format(fileName:)` handles case, aliases (`jpeg`, `tif`, `htm`) and compound `.tar.gz`/`.tgz`; UTType identifier per case. Tests: every case round-trips; ≥ 20 edge names (`a.TAR.GZ`, `.hidden`, `noext`, `x.JPEG`) | FR-07 |
| P0-11 | Content sniffer | Core | P0-10 | M | Pure `sniff(prefix:) -> SniffResult` identifies every binary input by magic bytes (ftyp brands for HEIC/AVIF/MP4/MOV, EBML doctype for MKV/WebM, RIFF subtypes, ZIP family flagged for caller disambiguation); a family mismatch with the extension returns the sniffed family and a reason. Tests: one byte fixture per format; empty and truncated input return nil without trapping | FR-07, FR-19 |
| P0-12 | Catalog: conversion pairs | Core | P0-10 | M | `Catalog.conversions(for:)` returns targets in the catalog's wheel order (01-prd §6.1). Tests: total = 275; per-input counts match the catalog table; no self-pairs; input-only formats never targets; `html` only as target; golden `catalog-pairs.json` diff is empty | FR-07 |
| P0-13 | Catalog: engine routes and phase tags | Core | P0-12 | M | Every pair → ordered `[EngineID]` per 10 §4.2–4.12 plus `phase` 1/2/3; extras (10 §4.14) carry `isExtra` and phase. Tests: every pair has ≥ 1 engine; phase counts 153 / 68 / 54; extras excluded from 275; `EngineID` values ⊆ 10 §4.1 codes | FR-07, FR-08 |
| P0-14 | Catalog: tools and actions | Core | P0-12 | M | 27 `ToolID`s with single/multi input sets in catalog order (01-prd §6.2), `isInstant` (mute, split PDF, extract, create PDF, read QR), `isMultiOnly`, output suffix (D-4), phase; 6 `ActionID`s in fixed order. Tests: per-input tool lists match a committed golden; actions independent of format; SF Symbol names chosen by us | FR-09, FR-10, D-4 |
| P0-15 | Selection resolver | Core | P0-12, P0-14 | M | Pure `resolve(selection:wheel:capabilities:) -> WheelContent`: intersection within one family (D-1); mixed families → badged union or "These files can't share a format" (D-1) [critic3: all copy here is Zivlet's own, 06d `EmptyReason`]; plain folders only on actions; `.pages`/`.rtfd` packages on conversions; any non-local or unreadable item → "Zivlet can't read one of these files"; none → "Nothing to work on yet"; no tools → "No tools for these items"; unavailable engines hidden with a recorded reason. Includes the minimal `CapabilitySnapshot` value type. Tests: ≥ 25 selection cases | FR-05, FR-08, FR-16 |
| P0-16 | OutputNamer | Core | P0-10, P0-14 | M | Pure naming: `<base>.<ext>`; `<base> <Suffix>.<ext>`; multi-input uses the first base; folder outputs and items (`Page 001`, `Clip 001`, `Frame 001 - 12.345s.png`, D-5); compound extensions stripped as a unit; `gz` target writes `.tar.gz`; `nextFreeName(_:existing:caseInsensitive:)` → `name 2.ext`, `name 3.ext`; NFC; truncate to ≤ 255 UTF-8 bytes without splitting graphemes. Tests: ≥ 40 cases incl. `a.PNG` vs `a.png`, emoji, 300-byte names | FR-11, D-5 |
| P0-17 | Job value types | Core | P0-13 | M | `JobRequest`, `JobItem`, `ConversionOptions` (per-output defaults per 11 §10), `ToolOptions`, `JobResult`, `StagedOutput`: immutable structs, `Sendable`, `Codable`, `Equatable`; `validate() throws(JobError)` rejects out-of-range values (quality ∉ [0, 1], speed ∉ [0.25, 4], empty items). Tests: JSON round-trip per type; validation table | FR-13, FR-15 |
| P0-18 | Error taxonomy and copy | Core | P0-17 | S | `JobError` cases per 10 §8.4 with pure `userMessage` and `logContext`; every case has non-empty copy; tests assert no message contains an absolute path | FR-15 |
| P0-19 | Progress model and throttle | Core | P0-17 | S | `JobProgress`, `BatchProgress` (cost weights: duration × pixels, pages, bytes), `ProgressThrottle` ≤ 10 Hz with an injected clock; nil fraction = indeterminate. Tests: weights sum to 1; intermediate samples dropped; final 1.0 always emitted | FR-14 |
| P0-20 | Settings model | Core | P0-17 | S | `ZivletSettings` immutable `Codable` value with defaults (⇧/⌘/⌃, sound+haptics on, glass theme, output beside original, Downloads fallback, Terminal); schema version + migration; unknown keys ignored. Tests: `{}` decodes to defaults; v0→v1 migration | FR-21, O-14 |

### 3.3 Group 0C — Trigger and wheel pure logic [TDD]

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P0-21 | Modifier masks and bindings | Trigger | P0-20 | S | `ModifierMask` (⌃⌥⇧⌘ only); defaults ⇧ convert / ⌘ tools / ⌃ actions; 15 combos per wheel; picker excludes combos bound to other wheels; empty and duplicate bindings rejected. Tests cover all three rules | FR-01 |
| P0-22 | Trigger trace schema and fixtures | Trigger | P0-21 | S | `InputSample` `Codable`; ≥ 10 JSON traces: Finder drag + ⇧; ⌘-held move drag; modifier held before drag; double tap; ⇧→⌘ switch; ⇧⌘ chord; ⇧ with no drag; button up with wheel open; Space change; text-only drag | FR-01, FR-02 |
| P0-23 | TriggerMachine | Trigger | P0-22 | L | Pure `step(_:) -> [TriggerEffect]`, idle → armed (button down, changeCount snapshot) → live (changeCount advanced and `dragHasFiles`) → wheel. Show on press-edge exact match, checked Tools → Conversion → Actions; key release never changes the wheel; another bound mask → `switchTo` unless the new wheel rejects the items (old wheel stays); unbound chord ignored; re-tap → `hide(.retap)` (D-2); held-at-drag-start ignored (D-3); 40 ms debounce after drag start; button up → idle; Space change → hide. Tests: golden effects per P0-22 trace; property test: no `show` without a file drag; ≥ 95 % branch coverage | FR-01, FR-02, D-2, D-3 |
| P0-24 | Wheel geometry | Wheel (nonisolated) | P0-02 | M | Constants in points: hub 42.24, petal inner 48.64, outer 119.52, ring 125.92, gap 4, corner inset 20.16, label radius 84.53, panel 372. Slot centre `θ = (n == 3 ? π : π/2) − 2πi/n`; n = 1 full ring, n = 2 halves; petal outline keeps the gap constant via `asin((gap/2)/r)`; corner insets `min(0.24·span, 0.15)` outer, `min(0.18·span, 0.18)` inner. Tests: n = 1…12 angles; gap = 4 ± 0.01 at inner and outer radii; sampled petals never overlap | FR-03 |
| P0-25 | Hit tester | Wheel (nonisolated) | P0-24 | M | Pure `hitTest` → `.hub`, `.slot(i)`, `.outside`; no `.gap` result (03 "Changes to sibling docs") [critic3]. Exact mode = petal-path containment, a separate `petalContains` predicate (06d 7b). Forgiving mode (default): gaps snap to nearest slice, slack out to r 150 pt, hub (r < 42.24) is a dead zone, 3° angular boundary hysteresis against the current slot [critic3: was "2 × ring radius" and "120 ms" from 14 §2.2; 03a §2.4 and M1 Task 7 use 150 pt / 3°]. Tests: centres, gaps, rim, r 150, hub; hysteresis at span/2 ± 3°; exact mode agrees with path containment on 10,000 random points | FR-04 |
| P0-26 | Panel placement | Wheel (nonisolated) | P0-24 | S | Pure `panelFrame(pointer:screens:)`: screen containing pointer (else main), 372 × 372 centred on pointer, clamped to `visibleFrame`, returns the anchor offset when clamped. Tests: four corners, menu bar, Dock side, two displays with negative origins | FR-03 |
| P0-27 | WheelModel reducer | Wheel (nonisolated) | P0-15, P0-25 | M | Immutable `WheelState` + `reduce`: open(kind, content); switch clears highlight; pointer sets highlight; gap keeps last hub label without highlight; hub/outside restores idle label; hub text "5 files · 48 MB"; empty-state pill from resolver; drop → `.apply(slot)` or `.refuse`. Tests: event-sequence goldens | FR-04, FR-05, FR-16 |
| P0-28 | Drag-operation negotiation | Wheel (nonisolated) | P0-02 | S | Pure `negotiate(mask:hit:)`: on a slice returns the first of copy, generic, link, move present in the mask; hub, gap and outside return nil (refuse); never implies a destructive operation. Tests: 16 masks × 4 hit kinds | FR-02, C-8 |

### 3.4 Group 0D — Spikes and infrastructure (each spike writes `docs/plan/spikes/<ID>.md`: result, data, decision)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P0-30 | G-0: macOS 26.x re-probe | Spike | P0-34 | M | ImageIO readable/writable UTIs (AVIF write), Vision request availability, ffmpeg encoder list, WKWebView print path re-run on 26.0 and latest 26.x; diff table vs 27.0; every diff has a fallback switched on; drag-pasteboard URL read with `EnablePasteboardPrivacyDeveloperPreview` shows no alert | G-0 **[HW]** |
| P0-31 | Trigger spikes | Spike | P0-40 | M | With the dev sampler on 26.x and 27.x: mouse monitors fire during Finder, Mail, Safari, Chrome drags with no TCC entry (P-T1); `flagsChanged` edges < 2 ms without permission (P-T2); Carbon Esc hotkey closes the wheel while the Finder drag continues (P-T3); drop accepted with ⌃/⌘/⌥ still held in all four sources, source never moved (P-T6); 1 kHz mouse monitor < 1 % CPU on M1 | P-T1, P-T2, P-T3, P-T6 **[HW][QA]** |
| P0-32 | Wheel render + latency spikes | Spike | P0-42 | M | Glass highlight and 6↔12 petal morph in a transparent `.popUpMenu` panel over full-screen video: no hitch > 2 frames, GPU < 10 % on M1 (P-W1, P-W2); tap → first frame p95 ≤ 16 ms at 120 Hz, ≤ 33 ms at 60 Hz (P-T4); idle RSS measured and the §8.10 bar replaced with data | P-W1, P-W2, P-T4 **[HW]** |
| P0-33 | Write-location prompts | Spike | P0-40 | S | Table: Desktop, Documents, Downloads, iCloud Drive, external disk, SMB — prompt or not when the app and a spawned ffmpeg write a sibling; onboarding copy drafted from it | P-P1 **[QA]** |
| P0-34 | Self-hosted Tart host | CI | — | M | Apple-silicon Mac mini registered as a self-hosted runner; Tart images 26.0, latest 26.x, latest 27.x with no Homebrew, Office or iWork; smoke job boots each and prints `sw_vers` | P-CI, C-10 **[OWNER][HW]** (purchase) |
| P0-35 | swift-subprocess under Swift 6.4 | Spike | P0-02 | S | swift-subprocess 1.0.2: `processGroupID = 0`, teardown SIGINT → SIGKILL at +1 s kills grandchildren of `sh -c 'sleep 100 & sleep 100'` within 1 s, QoS set, streamed stdout/stderr; else switch to `Foundation.Process` | M-4 |
| P0-36 | Vendor FFmpeg build | Vendor | P0-01 | L | `Vendor/versions.lock` + `build-media.sh`: FFmpeg 9.0.2 GPLv3 shared, arm64, minos 26.0, `--disable-network`, `--disable-demuxer=hls,dash,webm_dash_manifest,sdp,rtsp,rtp`, encoders libmp3lame, libopus, libvorbis, libvpx-vp9, libsvtav1, x264, VideoToolbox; `verify-media.sh`: no `nonfree`, `-L` says GPL v3, `otool -L` has no Homebrew paths, stripped size ≤ 30 MB | M-1, O-4 |
| P0-37 | vendor.yml workflow | CI | P0-36 | M | On `Vendor/**` change: cached `zivlet-vendor-<lockhash>.tar.zst`, source tarball, SPDX fragment; reproducibility job builds twice with equal hashes | 10 §11.1, X4 |
| P0-38 | Helper signing + release dry run | Release | P0-04, P0-36, P0-39 | L | `sign-helpers.sh` signs inside-out with `--options runtime --timestamp`; `verify-signatures.sh` passes; notarize, staple, signed DMG; Sparkle 2 N-1 → N update installs on a clean Tart VM; `spctl -a -vv` accepts; decision recorded on Xcode Code-Sign-On-Copy | M-2, P-C1 **[OWNER: Developer ID][HW]** |
| P0-39 | Owner decisions | Owner | — | S | Recorded in `00-decisions.md`: O-10 bundle id / domain / GitHub org; O-11 account holder and Sparkle key custody (offline backup); O-12 trademark check for "Zivlet"; O-18 1.0 scope and date; D-1…D-5 confirmed or overridden | O-10, O-11, O-12, O-18 **[OWNER]** |

### 3.5 Group 0E — Dev app shell (delivers M2)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P0-40 | AppKit InputSampler | Trigger | P0-23, P0-04 | M | Global + local `NSEvent` monitors (mouse down/dragged/up); changeCount snapshot; types-only check (file URL + promise types, no data reads); display-link sampler only while live; 2 Hz button watchdog only while armed/live; feeds `TriggerMachine`. Instruments: 0 Zivlet wakeups over 60 s idle. Debug menu "Record trigger trace" writes P0-22 JSON | FR-01, FR-24, 14 §1.3 **[QA]** |
| P0-41 | WheelPanel + WheelDropView | Wheel | P0-26, P0-27, P0-28, P0-40 | L | Borderless non-activating `NSPanel` at `.popUpMenu`, all Spaces + full-screen auxiliary, pre-warmed at launch, sized to the panel only (a Finder drop 1 pt outside the disc behaves normally); `WheelDropView` handles `draggingEntered/Updated/performDragOperation`, returns within 1 ms; hub returns false (snap back); URLs read only at drop; release inside without a drop → 150 ms release timeout (03a §1.5), then hide | FR-02, FR-03 **[QA]** |
| P0-42 | Glass and Solid wheel views | Wheel | P0-41 | M | SwiftUI petals in one `GlassEffectContainer`, model-driven highlight (radial accent gradient, white labels); Solid theme automatic under Reduce Transparency; bloom 200 ms scale 0.45 → 1 (none under Reduce Motion); instant close; labels 12 pt semibold (formats) and 7.5 pt + 12.6 pt symbol (tools/actions); empty-state pill 276 × 58. Snapshot tests of the Solid theme for n = 1…9 | FR-03, FR-04, FR-05 |
| P0-43 | Dev drop logger | App | P0-41 | S | Debug only: drop on a slice logs the `JobRequest` JSON and shows it in a dev HUD; this is the M2 demo | M2 |

---

## 4. Phase 1 — MVP slice, private alpha 0.1 (about 7–9 weeks)

Scope: 153 pairs (raster 49, audio 56, video 42, GIF 6), 5 actions, runtime, release pipeline (10 §12).

### 4.1 Group 1A — Engine contracts and pure planners [TDD]

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P1-01 | EngineKit contracts | EngineKit | P0-17 | M | `Engine`, `ExecutionPlan`, `Stage` (`.ffmpeg`, `.imageIO`, `.webp`, `.quartz`), `Lane`, `OutputSpec`, `VerificationSpec`, `InputProbe` as `Codable`/`Sendable`/`Equatable` values per 10 §7.3; `stageWeights` must sum to 1. Tests: JSON round-trip; bad weights throw | 10 §7.3 |
| P1-02 | MediaInfo + ffprobe JSON parser | EngineMedia | P1-01 | M | Pure parser of `ffprobe -print_format json -show_streams -show_format` → `MediaInfo` (codec, profile, pix_fmt, HDR transfer, rotation, duration, `attached_pic`, channels, sample format). Tests: ≥ 15 committed JSON fixtures incl. HDR HEVC, rotated iPhone MOV, MKV with subs + fonts, audio with cover, video without audio; malformed JSON → typed error | FR-18 |
| P1-03 | Input-confinement policy | EngineMedia | P1-02 | S | Advertised demuxer whitelist; probe argv carries `-format_whitelist`; every run argv starts `-nostdin -hide_banner -protocol_whitelist file,pipe -f <demuxer>`; concat/image2/ffmetadata only for Zivlet-written job files. Tests: argv assertions; probe results reporting hls/concat formats are rejected at plan time | FR-19, C-4 |
| P1-04 | Audio argv planner | EngineMedia | P1-02, P1-03 | M | 56 audio pairs + mp3-from-video per 11 §10.1: encoders, defaults, rate/channel/depth rules, cover handling, remux-first, `-map_metadata 0` unless disabled; Ogg forces libvorbis; Opus at 48 kHz. Tests: golden argv per pair; option validation | FR-07, FR-18, O-16 |
| P1-05 | Video argv planner | EngineMedia | P1-02, P1-03 | L | 42 video pairs (6 inputs × mp4/mov/mkv/webm/avi/wmv/gif/mp3 minus self) per 11 §10.2–10.3: remux-first by allowed sets; AVFoundation-playable predicate gates copy into MP4/MOV (AV1 only with HW decode; HEVC tagged `hvc1`); HDR → SDR tone-map chain for 8-bit targets; odd-dimension scale; subtitles → mov_text / webvtt / dropped with a note; WebM = VP9 + Opus; AVI CBR MP3; GIF palette pipeline. Tests: golden argv per pair × {SDR H.264, HDR HEVC, AV1, odd dims}; predicate table | FR-07, FR-18, C-9, O-16 |
| P1-06 | GIF-input argv planner | EngineMedia | P1-05 | S | 6 gif → video pairs per 10 §4.6: alpha flattened (noted) for MP4/MKV, HEVC-alpha MOV, VP9 `yuva420p` WebM, cfr ≤ 50 fps for AVI/WMV. Tests: golden argv | FR-07 |
| P1-07 | ffmpeg progress parser | EngineMedia | P1-01 | S | Pure parser of `-progress pipe:1` blocks → fraction (`out_time_us / expected`), ETA from `speed=`, stall when `out_time` is flat for 60 s (injected clock), multi-pass weights. Tests: recorded transcripts | FR-14 |
| P1-08 | Image plan builder | EngineImage | P1-01 | L | Pure `ImagePlan` for the 36 ImageIO raster pairs (49 minus 6 → webp minus 7 → pdf): destination UTType, quality default (03b quality ladder), keep ICC unless "Web (sRGB)", orientation once, 16-bit where allowed, animation carried (APNG/HEICS) else warning, alpha → JPEG flatten + note, HDR tone-map flag, metadata carry, AVIF route chosen from the capability snapshot. Tests: plan goldens per pair × {8-bit sRGB, 16-bit P3, animated, alpha, HDR gain map} | FR-07, FR-18 |
| P1-09 | WebP plan builder | EngineImage | P1-08 | S | `WebPPlan` for the 6 → webp pairs: lossy quality default, animated → `WebPAnimEncoder`, ICC/EXIF/XMP via mux, no silent lossless fallback larger than the source. Tests: option goldens | FR-07, FR-18 |
| P1-10 | Images → PDF plan builder | EnginePDF (new target) | P1-08 | S | `PDFPlan` for the 7 → pdf pairs: page size from pixels at 72 DPI, JPEG embed flag, multi-page TIFF → one page per frame, animated WebP → first frame + note. Tests: page-size math, frame enumeration | FR-07, FR-18 |
| P1-11 | Capability parsers and route filter | EngineKit | P0-13, P0-15 | M | Pure parsers for `ffmpeg -encoders/-muxers/-filters` and ImageIO UTI arrays → `CapabilitySnapshot`; cache key = binary SHA-256 + OS build; routes filtered with hidden reasons. Tests: missing libsvtav1 hides only the AV1 option; AVIF unwritable switches to the ffmpeg fallback route | FR-08, 10 §8.8 |
| P1-12 | Async semaphore and lane table | Runtime | P0-17 | M | Cancellation-aware async semaphore (about 40 lines); `LaneTable` widths from P-core count; memory pressure `.warning` halves, `.critical` pauses admission; Low Power halves `cpu`. Tests: width respected under 100 waiters; a cancelled waiter throws and leaks no permit | FR-13 |
| P1-13 | Disk preflight and location policy | Runtime | P0-17 | S | Pure `preflight` (free ≥ 1.5 × estimate + 512 MB else `diskFull`); location policy beside → Downloads fallback for read-only volumes. Tests: threshold and fallback tables | FR-17, O-14 |
| P1-14 | NameReserver actor | Runtime | P0-16 | S | Reserves names across concurrent jobs, released on publish or failure. Test: 200 concurrent reservations in one folder are all distinct (`name 2` … `name 201`) | FR-11 |
| P1-15 | UndoLog model | Runtime | P0-17 | S | Immutable `UndoEntry` (outputs → Trash, moves → reverse), history of 50, JSON persistence, pure revert planning. Tests: revert plans for convert and move; missing files reported, never ignored | FR-10, FR-14 |

### 4.2 Group 1B — Engine execution (integration)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P1-20 | SubprocessRunner | EngineKit | P0-35, P1-01 | M | Fixed child env (`PATH=/usr/bin:/bin`, `LC_ALL`, private `TMPDIR`), process group, teardown SIGINT → SIGKILL at +1 s, 64 KB stderr tail, line stream for progress, `job.json` PID file. Integration tests with `/bin/sh`: cancel kills the group ≤ 1 s; non-zero exit → `processFailed`; signal → `crashed` | FR-13, 10 §8.3 |
| P1-21 | EngineLocator | EngineKit | P1-20 | S | Bundled `Contents/Helpers` first; Debug-only (`#if DEBUG`) fallback to `/opt/homebrew/bin`; test asserts the Release build contains no Homebrew path string | FR-19, M3 |
| P1-22 | Capability probe runner | EngineKit | P1-11, P1-21 | S | Runs probes at first launch and after an update/OS change; writes `Capabilities/<hash>-<osBuild>.json`; reuses a matching cache. Test: second launch spawns nothing | FR-08 |
| P1-23 | MediaEngine execute + verifier | EngineMedia | P1-04…P1-07, P1-20 | L | Executes plans into the job workspace; `OutputVerifier` re-probes: container and codecs match the plan, duration within 1 frame (video) or 50 ms (audio), stream count, WebM = VP9/AV1 + Opus; mismatch → `verificationFailed`. Integration tests on generated fixtures | FR-07, FR-18 |
| P1-24 | ImageEngine execute (ImageIO) | EngineImage | P1-08 | L | Executes `ImagePlan` via ImageIO/Core Image with thumbnail-capped decode where possible and a 200 MP cap; verifier checks dimensions, colour space, alpha, frame count; HEIC 12 MP → JPEG ≤ 150 ms on M1 (nightly signpost) | FR-07, FR-18, FR-24 |
| P1-25 | libwebp xcframework + encoder | Vendor, EngineImage | P0-37, P1-09 | M | `build-native.sh` builds libwebp 1.6.0 → `CWebP.xcframework` (checksummed `binaryTarget`); encoder supports `WebPEncode`, `WebPAnimEncoder`, mux metadata; verifier decodes output. Tests: 6 → webp pairs; animated input keeps frame count | FR-07 |
| P1-26 | Images → PDF (Quartz) | EnginePDF | P1-10 | M | `CGContext(url:mediaBox:)`; JPEG embedded byte-for-byte; multi-page TIFF → multi-page PDF; verifier checks page count, page size, embedded JPEG stream hash = source | FR-07, FR-18 |

### 4.3 Group 1C — Runtime

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P1-30 | JobWorkspace + Publisher | Runtime | P1-13, P1-14 | M | Staging in `itemReplacementDirectory` on the destination volume (fallback hidden `.zivlet-<uuid>`); publish with `renamex_np(RENAME_EXCL)`, next name on EEXIST; `com.apple.quarantine` copied from any input to every output; source never overwritten; staging removed on failure or cancel. Integration tests: case-insensitive collision; simulated crash leaves no visible partial file | FR-12, C-5 |
| P1-31 | JobScheduler | Runtime | P1-12, P1-23, P1-24, P1-30 | L | Actor runs Request → Probe → Plan → Admit → Execute → Verify → Publish → Report with one immutable value per step; per-plan lanes; bounded batch fan-out; per-file failure isolation; cancel visible ≤ 100 ms with staging removed; quit waits ≤ 2 s. In-process in Phase 1 (XPC in P2-01). Tests with fake engines: lane widths, cancellation, 200-file batch with distinct outputs | FR-13 |
| P1-32 | OrphanReaper | Runtime | P1-20 | S | At launch, for each `Jobs/<uuid>/job.json`: if `proc_pidpath(pid) == helperPath`, `killpg(pgid, SIGKILL)`; delete the folder; sweep scratch older than 24 h. Tests: fake job folders; a live `sleep` child is reaped | FR-13, X19 |
| P1-33 | Drop → job wiring | App | P0-43, P1-31 | M | Drop on a conversion slice builds a `JobRequest` from the URLs and resolver content and submits it; output lands beside the original; one Finder reveal per batch. Demo set: jpg→png, png→webp, heic→jpg, mov→mp4, wav→mp3, mp4→webm (Homebrew ffmpeg) | M3, FR-07 **[QA]** |

### 4.4 Group 1D — UI surfaces

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P1-40 | Progress HUD | UI | P0-19, P1-31 | M | 360 × 108 non-activating panel near the pointer, 24 pt cascade per concurrent drop; title "Converting to <EXT>" or tool verb; "name · i of n · pct%"; indeterminate bar + bytes when duration is unknown; Cancel; visible ≤ 50 ms after drop (signpost) | FR-14 |
| P1-41 | Result card + Undo | UI | P1-15, P1-40 | M | Done state: thumbnail, before → after size, Undo (outputs to Trash; folder listing equals the pre-job listing), Reveal, Open, Copy, drag-out; errors persist with reason, "Show details" (stderr tail), Retry. XCUITest with a fixture job | FR-14, FR-15 |
| P1-42 | Mode switching and cancel paths | Wheel, UI | P0-23, P0-41 | M | ⇧/⌘/⌃ switch in place with a glass morph (crossfade under Reduce Motion) and highlight reset; re-tap closes (D-2); hub drop snaps back; Esc hotkey registered only while visible (per P0-31); Space change hides. Checklist `docs/plan/qa/trigger.md` passes | FR-02 **[QA]** |
| P1-43 | Sound and haptics | Wheel | P0-41 | S | Our own tick sound (self-made or CC0, licence recorded) + `NSHapticFeedbackManager` on highlight change; one setting gates both, default on; ≤ 1 tick per 30 ms | FR-06 |
| P1-44 | Actions: Copy, Copy Path, AirDrop | UI | P0-14, P0-41 | M | Copy writes file URLs to the general pasteboard; Copy Path joins POSIX paths with newlines (⌥: shell-quoted, space-joined); AirDrop via `NSSharingService(.sendViaAirDrop)` after `canPerform`; non-local items refused with 10 §6 copy. Unit tests on path formatting and quoting; AirDrop checked manually | FR-10 **[QA]** |
| P1-45 | Actions: Move, Terminal | UI | P1-15, P1-44 | M | Move: "Move Here" panel above the wheel, collisions → "name 2", cross-volume copy + verify + trash, folder into itself refused, UndoLog entry. Terminal: folder (or a file's parent) opens in the chosen app (Terminal default; iTerm2, Ghostty, WezTerm, Warp when installed). Unit tests on the pure move planner; terminal list verified manually | FR-10, P-TERM **[QA]** |
| P1-46 | Menu bar + minimal Settings | UI | P0-20 | M | Menu: Settings, Practice, Pause, Quit; General pane (bindings with exclusion pickers, sound/haptics, theme, terminal, fallback folder); Advanced pane (Copy diagnostics); launch at login via `SMAppService.mainApp` | FR-21 |
| P1-47 | Onboarding, practice, TCC pre-prompts | UI | P0-33, P1-46 | M | ≤ 60 s flow: practice card with a bundled sample file teaches ⇧, ⌘, ⌃; optional coach and key legend for the first N drags; folder prompts explained per the P0-33 table. Usability: 5 of 5 testers finish a conversion unaided | FR-21 **[QA]** |
| P1-48 | Diagnostics and logging | Runtime, UI | P1-31 | S | `Logger` categories per 10 §8.7 with `.private` paths; signposts for trigger → frame, drop → admit, per stage; "Copy diagnostics" bundles helper hashes, capability cache, last 200 log lines, last trigger trace, settings; no network. Test: bundle has no unredacted home path | FR-20 |

### 4.5 Group 1E — Vendor integration and release

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P1-50 | Bundle ffmpeg helpers | App | P0-37, P1-21 | M | XcodeGen copy phase places vendor ffmpeg/ffprobe + dylibs in `Contents/Helpers` (non-Mach-O in `Resources`); Release locator finds them; `SecStaticCodeCheckValidity` with the Team-ID requirement on first use (skipped for ad-hoc Debug) | FR-19, C-2 |
| P1-51 | Licence gate + GPL source bundle | Release | P1-50 | M | `source-bundle.sh` produces corresponding source for every bundled GPL/LGPL component; SPDX manifest complete; About › Acknowledgements lists licences; CI fails on `nonfree` or a missing licence entry | FR-23, X16 |
| P1-52 | Signature and size gates | Release | P0-38, P1-50 | S | `verify-signatures.sh`: every Mach-O has the runtime flag and a timestamp, `codesign --verify --strict` passes; `size-gate.sh` fails above 85 MB installed / 40 MB DMG, warns above 70 / 32 | FR-23, FR-27 **[OWNER]** |
| P1-53 | release.yml + Sparkle stable | Release | P1-51, P1-52 | L | Tag `v*` → archive, inside-out signing, notarize, staple, DMG, notarize DMG, `spctl` smoke on a Tart VM (one pair per engine), EdDSA-signed appcast with deltas, GitHub release with source, SBOM, dSYMs; protected `release` environment; N-1 → N update verified | FR-23 **[OWNER][HW]** |

### 4.6 Group 1F — Verification and alpha

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P1-60 | Fixture generator | Fixtures | P0-36 | M | `Fixtures/generate.sh` deterministically makes media (lavfi `testsrc2`/`sine`: SDR, HDR, rotated, odd dimensions, 5.1, cover art, subtitles) and images (8/16-bit, P3, alpha, animated, multi-page TIFF, HDR HEIC); output hashes recorded; small set committed, large set in LFS | FR-18 |
| P1-61 | Pair matrix (153) | QA | P1-23…P1-26, P1-60 | L | `@Test(arguments:)` over every Phase 1 pair: output decodes; property checks (dimensions, colour space, alpha, frames, duration ± 1 frame, codecs); WebM VP9/AV1 + Opus; MP4/MOV `AVURLAsset.load(.isPlayable)` true. PR runs a subset, nightly all 153; 0 failures | FR-07, M-COPY |
| P1-62 | Hostile media corpus | QA | P1-03, P1-23 | M | HLS playlist named `.mp4`, ffconcat named `.mkv`, truncated MP4, 60,000 × 60,000 PNG header, zip renamed `.tiff`: each refused with user copy or contained; no output contains bytes from files outside the input | FR-19, M-HOSTILE |
| P1-63 | Performance signposts | QA | P0-32, P1-24 | M | Nightly on Apple silicon: tap → wheel p95, drop ack, HEIC → JPEG, 1-min 1080p MOV → MP4 ≤ 10 s, idle wakeups 0; compared with 10 §8.11; a regression > 10 % fails | FR-24 **[HW]** |
| P1-64 | Real-drag QA matrix | QA | P1-33, P1-42 | M | Finder, Desktop, Safari, Chrome, Photos, VS Code, Dropover running, full-screen Space, two displays (mixed refresh), Stage Manager: pass or logged; promise sources (Mail, Photos) listed as "Phase 2" | FR-01, FR-02 **[QA][HW]** |
| P1-65 | Alpha 0.1 | Release | P1-01…P1-64 | S | M4 exit checks pass; `v0.1.0-alpha` tagged; private tester list | M4 **[OWNER]** |

---

## 5. Phase 2 — Breadth, public beta 0.5 (about 10–14 weeks)

Scope: +68 pairs (→ 221), 19 of 27 tools, Float (6 of 6 actions), worker XPC, Services, beta channel, extras. Each engine task starts with its pure planner and goldens [TDD], then execution.

### 5.1 Platform and spikes

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P2-01 | ZivletWorker.xpc + WorkerClient | Runtime | P1-31 | L | Engines run in an XPC service with `Codable` plans; worker crash → each in-flight job retried once, singly; a second crash → "This file made the engine crash" and the batch continues; in-process fallback. Test: injected crash fixture | FR-13, X8 |
| P2-02 | Promise drags | Trigger, Runtime | P1-33 | M | `NSFilePromiseReceiver` into staging; outputs to the Downloads fallback; per-source table (Mail, Photos, Safari, Chrome, Arc, Firefox) works or is listed unsupported | FR-17, P-T5 **[QA]** |
| P2-03 | Gate B media spikes | Spike | P1-23 | M | M-3 VT presets, M-5 SVT-AV1 still AVIF, M-6 AIFF/WMA cover art, M-COPY drift ≤ 1 frame and `isPlayable` on M1 + M3, M-META no GPS left: decision records written, fallbacks switched | M-3, M-5, M-6, M-COPY, M-META **[HW]** |
| P2-04 | Gate B image/PDF/archive spikes | Spike | P2-10, P2-13, P2-19 | M | I-S1 ≥ 97 % equal on 500 SVGs; I-PDF1 < 1 % failures; I-PDF2 drop list; I-PDF3 extractable text; I-A1 hostile archives contained; I-M1 Perl < 6 MB, XS bundles notarize; I-M2 ≥ 20 files/s, no leaks over 1,000 jobs | I-S1, I-PDF1–3, I-A1, I-M1, I-M2 |
| P2-05 | Gate B document spikes | Spike | P2-14, P2-16 | L | D-JS (all libs run, warm call < 50 ms), D-SHEET (100 % values, 2 M cells < 15 s), D-RENDER (median SSIM ≥ 0.80, ≤ 2 s / 30 slides), D-PAGES, D-PRINT2 (else render width stays 1), D-XLSX-STYLE: decision records | D-JS, D-SHEET, D-RENDER, D-PAGES, D-PRINT2, D-XLSX-STYLE **[HW]** |
| P2-06 | Gate B platform spikes | Spike | P1-46 | S | P-X1 Services entry + shortcut opens the wheel with no prompt; I-V1 first OCR < 3 s after warm-up on 26.x | P-X1, I-V1 **[HW]** |

### 5.2 Conversions (+68)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P2-10 | ZivletRS Rust library | Vendor | P0-37 | M | `resvg ~0.47` + `krilla-svg 0.8.1` + oxipng + libimagequant → `ZivletRS.xcframework`; `cargo tree -d` shows no duplicate usvg/resvg/tiny-skia (CI fail); `cargo-deny` licences and advisories pass | 10 §3 challenge |
| P2-11 | SVG: 8 pairs | EngineImage | P2-10 | M | RSVG raster (2× intrinsic, longest edge ≤ 8192), S2P vector PDF; resolver accepts only `data:`; matrix green for 8 pairs | FR-07, FR-19 |
| P2-12 | PDF → jpg/png/txt/md | EnginePDF | P1-26 | M | QZR at `s = min(300/72, 8192/maxSide, √(16e6/(w·h)))`, multi-page → `<base> <EXT> Pages/Page 001.<ext>` (D-5); txt/md from the PDFKit text layer; matrix green for 4 pairs | FR-07, D-5 |
| P2-13 | qpdf xcframework | Vendor | P0-37 | S | qpdf 12.4.2 + libjpeg-turbo → `CQPDF.xcframework`; licence entries; smoke test rewrites a PDF | 10 §3 |
| P2-14 | zivlet-js helper + JSClient | JSHelper, EngineDocs | P1-20 | L | Separate helper with JSContext, JSON over stdio; only it has `allow-jit`; one warm instance kept 60 s; esbuild IIFE bundles with hash manifest; watchdog 60 s. Tests: echo round-trip, crash → typed error | 10 §1 R-2 |
| P2-15 | Spreadsheets: 21 pairs | EngineDocs | P2-14, P2-16 | L | SheetJS read/write xlsx/ods/csv/tsv; SJS → WKP for PDF (gridlines, number formats, merges, header repeat, auto-landscape); D-SHEET bars met | FR-07, FR-26 |
| P2-16 | RenderHost | EngineRender | P0-02 | L | `@MainActor` WKWebView pool created lazily and torn down after 60 s idle; content rules block http(s)/file/ftp; non-persistent store; print to PDF; snapshot; render lane width 1 unless D-PRINT2 passes | FR-19, FR-26 |
| P2-17 | PPTX: 3 pairs | EngineDocs | P2-16 | M | pptx-renderer → vector PDF; PNG/JPG via 2× snapshot per slide into `<base> Slides/`; D-RENDER bar met | FR-07, FR-26 |
| P2-18 | Subtitles: 4 pairs | EngineSubtitles | P0-02 | M | Pure SRT/VTT parser and writer [TDD]; nightly fuzzing with `-sanitize=fuzzer`; matrix green | FR-07, FR-19 |
| P2-19 | Archives: 9 pairs | EngineArchive, Vendor | P0-37 | L | libarchive 3.8.10 (+ xz, zstd, lz4) xcframework; streaming re-pack; no `..`, symlinks or absolute paths; size, entry and ratio limits per 10 §8.9; quarantine propagated to every output; I-A1 corpus contained | FR-07, FR-12, FR-19, C-5 |
| P2-20 | SDoc model + txt/md/html/epub writers | EngineDocs | P0-02 | L | Immutable SDoc model [TDD]; writers W:txt, W:md, W:html, W:epub; EPUBCheck 0 errors on the corpus | FR-26 |
| P2-21 | md/txt readers + WKP: 12 pairs | EngineDocs | P2-16, P2-20 | M | MD-R (swift-markdown, GFM), TXT-R (encoding detection); WKP print with page numbers; md → txt/html/epub/pdf/png/jpg and txt → md/html/epub/pdf/png/jpg green | FR-07, FR-26 |
| P2-22 | DOCX: 7 pairs | EngineDocs | P2-14, P2-16, P2-20 | M | docx-preview → print for pdf/png/jpg (DXP); mammoth → SDoc for txt/md/html/epub (MAM); "Layout approximated" label when no break hints | FR-07, FR-26, X6 |
| P2-23 | Extras: video → m4a, animated WebP, AV1 option | EngineMedia | P1-05 | M | m4a stream copy when AAC; `libwebp_anim` output and animated-WebP input; WebM AV1 option via `libsvtav1`; goldens + matrix | 10 §4.14 |

### 5.3 Tools (19 of 27)

Shared acceptance for every tool row: pure plan builder with golden tests first; output name per P0-16 (D-4); verify step; progress and cancellation via the scheduler; options remembered.

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P2-30 | Tool window shell | UI | P1-46 | M | Shared chrome opens at the wheel location; Apply/Cancel; disabled-state reasons; bipolar sliders fill from centre; editable timecodes; XCUITest launch argument `-UITestFixture <dir>` | FR-09 |
| P2-31 | Compress: images | EngineImage | P2-10, P2-30 | M | IIO quality binary search [0.30, 0.92] ≤ 7 encodes, then −15 % pixel steps; WebP `target_size`; PNG imagequant + oxipng; output ≥ input → "Already optimal", nothing kept | FR-09, O-16 |
| P2-32 | Compress: audio and video | EngineMedia | P2-30 | M | Same codec at lower bitrate (wav/aiff → FLAC); VT HEVC presets + height cap; target size Fast (VT ABR, ≤ 3 retries × 0.92) and Accurate (x264 2-pass) | FR-09 |
| P2-33 | Compress: PDF | EnginePDF | P2-13, P2-30 | M | Quartz filter presets (Light / Balanced / Strong), 2-D target-size search ≤ 6 passes, qpdf lossless pass; forms/signatures/tags trigger a lossless-only offer | FR-09, I-PDF2 |
| P2-34 | Metadata view/edit/strip | EngineMetadata | P2-04, P2-30 | L | ExifTool `-stay_open` actor with bundled trimmed Perl (`/usr/bin/perl` fallback); ffmpeg strip drops `attached_pic` cover art; qpdf rewrite for PDF; verify contract: planned changes applied, nothing else changed, `ImageDataHash` unchanged, "Remove all" leaves no GPS/maker notes/XMP/IPTC/thumbnail | FR-09, O-8, M-META |
| P2-35 | Crop Image | EngineImage | P2-30 | S | `CGImage.cropping(to:)`, same-format encode; "Apply to all" proportional for multi | FR-09 |
| P2-36 | Normalize Volume | EngineMedia | P2-30 | S | EBU R128 two-pass `loudnorm`, measured values fed to pass 2, `linear=true`; presets −16/−14/−23 LUFS | FR-09 |
| P2-37 | Remove Audio (instant) | EngineMedia | P1-31 | S | `-map 0 -map -0:a -c copy`; no window; output `<base> Muted.<ext>` | FR-09 |
| P2-38 | Trim Video | EngineMedia, UI | P2-30 | M | Fast (keyframe copy, `-avoid_negative_ts make_zero`) and Exact (re-encode); AVPlayer preview or ffmpeg proxy (LRU 2 GB cache) | FR-09 |
| P2-39 | Split PDF (instant) | EnginePDF | P1-26 | S | PDFKit per page (qpdf `--split-pages` for large files) → `<base> Pages/Page 001.pdf` | FR-09 |
| P2-40 | Organize PDF | EnginePDF, UI | P2-30 | M | Reorder, rotate, delete in a thumbnail grid; "same width" scaling | FR-09 |
| P2-41 | Extract Archive (instant) | EngineArchive | P2-19 | S | Hardened extract into hidden staging, then rename to `<base> Extracted`; quarantine propagated | FR-09, FR-19 |
| P2-42 | Create PDF (instant, multi) | EnginePDF | P1-26, P2-11 | S | One page per image (+ SVG via S2P), JPEG bytes embedded; `<first base> Images.pdf` (D-4) | FR-09 |
| P2-43 | Merge PDFs (multi) | EnginePDF | P2-13, P2-30 | S | PDFKit insert keeping the first outline; qpdf `--empty --pages` when forms, encryption or signatures are present | FR-09 |
| P2-44 | Crop Video | EngineMedia, UI | P2-30 | M | `crop=w:h:x:y` even dimensions, rotation honoured, audio copied | FR-09 |
| P2-45 | Change Video Speed | EngineMedia, UI | P2-30 | S | `setpts` + chained `atempo`, 0.25×–4×, pitch preserved; `<base> Speed 2.0x.<ext>` (D-4) | FR-09 |
| P2-46 | Join Videos (multi) | EngineMedia | P2-30 | M | Concat demuxer + copy when parameters match; else first-clip canvas, `anullsrc` for missing audio, VT H.264 + AAC; concat list written only in the job folder | FR-09, C-4 |
| P2-47 | Video Snapshots | EngineMedia, UI | P2-38 | S | Frame grab for UI; export `-ss t -frames:v 1` PNG per timestamp; several → `<base> Snapshots/Frame 001 - 12.345s.png` | FR-09 |
| P2-48 | Split Video | EngineMedia, UI | P2-38 | M | Separate clips → `<base> Clips/Clip 001.<ext>`, or one video of kept segments → `<base> Edited.<ext>` | FR-09 |
| P2-49 | Trim Audio + auto silence | EngineMedia, UI | P2-30 | M | `-ss/-to` copy trim; `silencedetect` analysis (−80…−10 dB); waveform from `AVAudioFile` or `f32le` pipe | FR-09 |
| P2-50 | Convert Audio Channels | EngineMedia | P2-30 | S | Mono `-ac 1`, stereo pan, swap, dual-mono | FR-09 |
| P2-51 | Read QR Codes (instant) + EngineVision base | EngineVision, UI | P2-30 | M | Vision `DetectBarcodesRequest` (all listed symbologies), PDF pages at 200 DPI; results window Copy / Copy All; Open only for http(s), full URL shown, never auto-opened | FR-09, FR-19 |

### 5.4 Shell, verification, beta

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P2-55 | Float shelf | UI | P1-44 | L | Non-activating floating panel(s), all Spaces; edge dock (attach 28 pt / detach 48 pt) or free; compact/expanded, icons/list; QL thumbnails and Quick Look; drag-out; marquee, type-to-select, context menu; "new vs add to existing" setting; missing files greyed with "Locate…"; restored after relaunch | FR-10 |
| P2-56 | Services menu entry | App | P2-06 | S | "Open in Zivlet" for Finder selections; opens the wheel in keyboard mode at the pointer; no prompt | FR-25, P-X1 |
| P2-57 | Beta channel | Release | P1-53 | S | Settings › Updates opt-in; appcast `--channel beta`; phased rollout for minors | FR-23 |
| P2-60 | Matrix 221 + 19 tools + fidelity nightly | QA | P2-10…P2-51 | L | Nightly: all 221 pairs and 19 tools green; document fidelity corpus on a VM without Office/iWork; EPUBCheck 0 errors; hostile PDF/ZIP corpus isolated by the worker | FR-07, FR-09, FR-26 **[HW]** |
| P2-61 | Public beta 0.5 | Release | P2-01…P2-60 | S | M5 exit checks; O-12 name check done before this artifact; `v0.5.0-beta` | M5 **[OWNER]** |

---

## 6. Phase 3 — 1.0 parity (about 12–16 weeks)

Scope: remaining 54 pairs (→ 275), last 8 tools (→ 27), App Intents, CLI, Settings complete, accessibility, keyboard path.

### 6.1 Conversions (+54) and engines

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P3-01 | Gate C spikes | Spike | P2-20 | L | D-DOCX (page delta ≤ 1, SSIM ≥ 0.85), D-PDF (recall ≥ 98 %, table F1 ≥ 0.8), D-WRITERS (0 EPUBCheck errors, 0 repair prompts), D-LO (install < 3 min), P-CLI, P-X2, P-W3, P-W4, M-REDACT (≥ 1× realtime): decision records | gate C **[HW]** |
| P3-02 | W:docx writer | EngineDocs | P2-20 | L | Own WordprocessingML; opens in Word, Pages and LibreOffice without repair on the D-WRITERS corpus | FR-26 |
| P3-03 | RTF/RTFD/clipping readers + W:rtf | EngineDocs | P2-20, P3-02 | M | NSAS readers; rtf 9 + rtfd 9 + textClipping 9 pairs green | FR-07 |
| P3-04 | Pages read/write | EngineDocs | P2-14, P2-05 | L | cupertino-files CF-R/CF-W: pages → 8 and docx/md/txt → pages; if D-PAGES failed, Pages output via iW and Pages input via the embedded preview with a notice | FR-07, X5 |
| P3-05 | EPUB reader: 6 pairs | EngineDocs | P2-20 | M | ZIPFoundation + OPF spine + SwiftSoup; DRM/obfuscated fonts refused; XML DTD/ENTITY rejected | FR-07, FR-19 |
| P3-06 | md/txt → docx | EngineDocs | P3-02 | S | 2 pairs green (pages variants in P3-04) | FR-07 |
| P3-07 | PDF → docx/pages/pptx/xlsx/epub | EngineDocs, EngineVision | P3-01, P3-02 | L | FUS: PDFKit text layer + Vision `RecognizeDocumentsRequest` → SDoc → writers; D-PDF bars met | FR-07, FR-26 |
| P3-08 | Office engine (LibreOffice tier 2) | EngineDocs | P3-01 | L | Discovery of an existing install; optional download pinned by SHA-256 in the EdDSA-signed manifest, Team ID checked; private profile, macros Very High; batch runner with 120 s watchdog; PPT 3 pairs + odt/doc/odp extras | FR-07, O-5, O-6 |
| P3-09 | iWork bridge (opt-in) | App | P3-01 | M | Apple Events export via Pages/Keynote/Numbers, off by default; Keynote as PPT alternative | O-17 |
| P3-10 | Document fidelity router | EngineDocs | P3-08, P3-09 | S | Automatic (default), Fast, Best; result records engine and font substitutions. Tests: router table [TDD] | O-7 |
| P3-11 | Extras | EngineImage, EngineDocs | P3-02 | M | png/jpg/heic → docx via OCR; RAW/PSD/JXL/EXR/JP2 inputs; ICO (≤ 256 px) / ICNS outputs; md ↔ html | 10 §4.14 |

### 6.2 Tools (+8) — shared tool acceptance from §5.3 applies

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P3-20 | Edit Photo | EngineImage, UI | P2-30 | L | One P3 linear `CIContext` chain (exposure … grain); own Metal kernels for dehaze, clarity, texture; RAW via `CIRAWFilter` | FR-09 |
| P3-21 | Annotate Photo | EngineImage, UI | P2-30 | L | Own CoreGraphics/CoreText layer model (arrow, freehand, text, shapes, highlighter, counter, magnifier, pasted image) at full resolution → PNG | FR-09 |
| P3-22 | Add BG | EngineImage, UI | P2-30 | M | Gradient/colour presets, padding, radius, shadow, canvas ratio; optional Vision subject shadow | FR-09 |
| P3-23 | Create Collage (multi) | EngineImage, UI | P2-30 | M | Grid/horizontal/vertical/featured layouts in P3, ≤ 8192², options remembered | FR-09 |
| P3-24 | EngineVision: detection and warm-up | EngineVision | P2-51 | M | Faces, text, `detectedData` PII, `TrackObjectRequest`; background warm-up with "Preparing text recognition…" state | X12 |
| P3-25 | Redact Photo | EngineImage, UI | P3-24 | M | Faces (+15 %), text, PII auto-select + IBAN/card (Luhn)/ID regexes; solid (default), pixellate ≥ max(16 px, 4 % short edge), blur ≥ 30 px with warning; always strips metadata incl. EXIF thumbnail | FR-09, FR-19 |
| P3-26 | Redact Video | EngineMedia, UI | P3-24, P3-01 | L | One filter per track driven by `sendcmd`, or a mask video piped to `maskedmerge`; M-REDACT bar (10 min 1080p, 3 tracks ≥ 1× realtime) | FR-09, M-REDACT |
| P3-27 | Bleep Audio | EngineMedia, UI | P2-49 | M | Gated `volume` + inverse-gated 1 kHz sine, `amix=normalize=0`; video copied | FR-09 |
| P3-28 | Audio Visualizer | EngineMedia, UI | P2-30 | M | `showwaves` in our brand colour or a looped still; 16:9, 9:16, 1:1; VT H.264 + `aac_at` | FR-09 |

### 6.3 Platform, polish, release

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P3-30 | App Intents | App | P1-31 | M | Convert, Compress, Strip Metadata, Run Tool, Read QR, Extract Text, Images → PDF, Merge PDFs; `OutputFormat` AppEnum generated from `Catalog`; intents live in the app target | FR-25 |
| P3-31 | `zivlet` CLI + Homebrew cask | zivlet-cli | P2-01, P3-01 | M | `convert`, `tool`, `formats --json` (from Catalog), `info`, `wheel`; WebKit routes handed to the app (P-CLI); cask bump PR in release.yml | FR-25, P-CLI |
| P3-32 | Settings complete | UI | P1-46 | M | Per-output conversion defaults (per output kind), document fidelity, engines (install/uninstall LO), output location, Advanced; "Format compatibility" list from Catalog with hidden-route reasons | FR-21, FR-08 |
| P3-33 | Accessibility | UI | P3-34 | M | VoiceOver labels ("JPEG, 3 of 8"), Reduce Motion, Reduce Transparency, Increase Contrast; VoiceOver audit passes on wheel, HUD, Settings, tool windows | FR-22 |
| P3-34 | Keyboard path | UI | P2-56 | M | Keyboard-mode wheel: arrows, Home/End, 1–9, type-to-filter, Enter, Esc, petal focus ring; optional global hotkey (Apple Events Finder selection, opt-in); bare Enter never hijacked (Finder rename still works) | FR-22, O-17 |
| P3-35 | String catalog (English) | UI | P3-32 | S | All UI strings in String Catalogs; copy grammar reviewed; no hard-coded user-facing strings (lint) | O-15 |
| P3-40 | Full nightly matrix on clean VM | QA | P3-01…P3-28 | L | All 275 pairs, 27 tools, 6 actions green nightly on a clean macOS 26.x Tart VM (PPT with LibreOffice installed) | FR-07, FR-09, FR-10 **[HW]** |
| P3-41 | Release checklist, real-drag QA, size gate | QA | P3-40 | M | Real-drag matrix incl. promise sources; size ≤ 85 MB / 40 MB (target 70 / 32); signature, licence, source-bundle gates; performance budgets hold | FR-23, FR-24, FR-27 **[QA][HW]** |
| P3-42 | 1.0 release | Release | P3-41 | S | M6 exit checks; O-18 scope confirmed; "1.0" label only at full parity | M6 **[OWNER]** |

---

## 7. Backlog — Phase 4 (1.x) and Phase 5 (2.x)

Not scheduled. Each item becomes a full task row when its phase is planned. Items moved into the plan by the
2026-10-21 roadmap are listed in §9.9.

| ID | Item | Engine / note |
|---|---|---|
| B4-01 | Warm LibreOfficeKit helper | D-LO; `disable-library-validation` on that helper only |
| B4-02 | Styled XLSX → PDF | umya-spreadsheet (D-XLSX-STYLE) |
| B4-03 | HDR gain-map round trip | I-HDR |
| B4-04 | "Copy command" debug item; VMAF-calibrated VT presets | M-3 |
| B4-05 | Remove Background | Vision `GenerateForegroundInstanceMaskRequest`; macOS 27 refine behind `#available` |
| B4-06 | Make PDF Searchable (OCR) | I-PDF3 |
| B4-07 | PDF Protect, Unlock, Optimize, Fast Web View | qpdf |
| B4-08 | QR Generate | `CIQRCodeGenerator` |
| B4-09 | Batch Rename with token preview and Undo | own |
| B4-10 | JPEG XL output; jpegli | libjxl 0.12; I-C1 |
| B4-11 | Subtitle time shift, fps conversion, ASS/SSA/SBV input | SUB |
| B4-12 | 7z/xz/zst/iso/cab inputs; 7z, AES-ZIP, tar.xz/zst outputs | LA |
| B4-13 | keynote/numbers inputs | CF-R / iW |
| B4-14 | ~~Union-of-targets wheel with "applies to 3 of 5" badges~~ [critic3: moved into P0-15 / M1 Task 7 per D-1] | D-1 |
| B4-15 | Pinned presets, fit-under-size targets (10 MB, 25 MB), hover size estimates | UX |
| B4-16 | Customisable wheels | UX |
| B4-17 | Finder Sync extension (app group with Team-ID prefix) | 10 §11.2 challenge |
| B4-18 | Output location options: `Converted/` subfolder, Ask | O-14 |
| B4-19 | 10 languages | O-15 |
| B4-20 | Lossless JPEG MCU-aligned crop | EngineImage |
| B5-01 | MuPDF true redaction | O-9 gate **[OWNER]** |
| B5-02 | Sandboxed worker with FD passing | P-8 |
| B5-03 | Transcribe → SRT/VTT | whisper filter or Speech framework |
| B5-04 | Foundation Models "describe what you want" | on-device |
| B5-05 | Raycast extension; MCP server over the CLI | CLI |
| B5-06 | High-quality GIF palette (gifski or own) | — |
| B5-07 | Pandoc pack if corpus scores lag | optional download |
| B5-08 | Use locally installed Office fonts | O-19, legal review **[OWNER]** |

---

## 8. Owner and hardware dependency summary

| Task | Blocker | Workaround until resolved |
|---|---|---|
| P0-34, P0-30, P1-53, P1-63, P2-60, P3-40 | Mac mini Tart host with 26.0 / 26.x / 27.x images **[OWNER][HW]** | Run on the dev Mac (macOS 27) and tag results "27-only"; G-0 stays open and blocks M4 |
| P0-38, P1-52, P1-53 | Developer ID certificate + notarytool API key (O-11) **[OWNER]** | Ad-hoc signed dev builds; the signature gate runs in report-only mode |
| P0-04, P1-53 | Bundle id / domain / GitHub org (O-10) **[OWNER]** | Placeholder `app.zivlet.Zivlet` in one xcconfig variable; must be final before the first Sparkle-enabled build |
| P2-61, P3-42 | Trademark / name check (O-12) **[OWNER]** | No public artifact until done |
| P1-53 | Sparkle EdDSA key generation and offline backup custody **[OWNER]** | No appcast publishing |
| P0-31, P0-32, P1-63, P1-64 | M1 Air, 120 Hz MacBook Pro, 60 Hz external display **[HW]** | Latency bars marked unverified |
| P1-47, P1-64, P2-02, P3-41 | Human testers and real cross-app drags **[QA]** | None; required for M4 and later |
| D-1…D-5, O-18 | Owner confirmation **[OWNER]** | Defaults in §1.4 apply |

---

## 9. Roadmap additions for the owner's feature picks (2026-10-21)

Approved by the owner on 2026-10-21 ([00-decisions](../design/00-decisions.md)). IDs are as corrected by the
challenge pass ([17-roadmap-challenge.md](../design/17-roadmap-challenge.md)). Where §9.1 changes a row in §3–§7,
§9.1 wins.
Companion files: [17-feature-roadmap.md](../design/17-feature-roadmap.md) (sequencing and rationale) and
[01b-prd-additions.md](01b-prd-additions.md) (FR-90…FR-141, NFR-21…NFR-24).
Evidence: the cluster reports in `docs/design/`: `17a-pdf.md`, `17b-lock.md`, `17c-image.md`, `17d-media-ai.md`,
`17e-app.md`.

Clean-room rule, unchanged: behaviour and parameters come from our own docs and prototypes. No reference-app,
Open-Tangerine, Dropover, Yoink, NotchDrop, Boring Notch or NotchNook code, strings or assets.

---

### 9.0 Conventions used here

- Columns are the 05 §1.1 columns: ID · Title · Area · Deps · Size · Acceptance · Satisfies.
- **IDs ≥ 100 are additions from this roadmap** (`P2-100`, `P3-100`, `P4-100`). This avoids clashes with 05's existing
  rows and with the provisional IDs the cluster reports used (17a-pdf.md's "P2-44" collides with Crop Video; 17e-app.md's
  P2-70…73 and P3-50 are replaced). The cluster ID is kept in Satisfies (e.g. `lock L-02`) for traceability.
- Groups: wave 2A = P2-100…119, wave 2B = P2-120…139, wave 2C = P2-140…159, spikes = P2-190…199 / P3-190…199.
  Phase 3 = P3-100…, Phase 4 = P4-100… (Phase 4 rows replace the matching B4/B5 backlog lines, §9.9).
- Sizes: **S** ≤ 1 day · **M** 2–4 days · **L** 5–10 days, one engineer, ESTIMATE (05 §1.1).
- Flags: **[TDD]** pure logic, tests first · **[OWNER]** owner action/decision · **[QA]** manual QA · **[HW]** hardware.
- Satisfies: FR IDs refer to the PRD numbering (01-prd FR-1…FR-89, plus FR-90…FR-141 from 01b-prd-additions), not to
  05 §1.3's FR-01…FR-26 index.
- All password-handling rows inherit P2-102 (policy tests). All Vision rows inherit P2-103 (single process identity).
- [challenge] **Spike/QA IDs renamed to avoid clashes with 10 §13:** lock manual QA M-1…M-6 → **LK-M1…LK-M6** (10's
  M-1…M-6 are media spikes); I-C1 (oxipng/cjxl timings) → **I-C2** (10's I-C1 is jpegli/libavif); P-W4 (dwell ring) →
  **P-W5** (10's P-W4 is the UI-sound key); I-V2 is folded into the existing **I-V1/S-V1** row of P2-06, and P2-190
  extends it. The cluster reports keep their local names; this section is authoritative.

---

### 9.1 Changes to existing 05 rows

| ID | Change | New / extra acceptance |
|---|---|---|
| P2-13 | qpdf xcframework built with `-DREQUIRE_CRYPTO_NATIVE=ON`, **no OpenSSL** (17a-pdf.md D-PDF-8) | Smoke test decrypts an RC4-128 fixture (PDFKit-made) and an AES-256 fixture; `otool -L` shows no libcrypto; [challenge] qpdf is *static* in `ZivletEngines` (10 §10), so the check is "qpdf + libjpeg-turbo contribution ≤ 4.5 MB (10 §9 expected)", not "dylib ≤ 4 MB" |
| P2-19 | Archive engine grows to the expanded format set (§9.5 P2-147/148); libarchive patched to write NFC names (P2-113); worker calls `setlocale(LC_CTYPE,"UTF-8")` | ZIP entry names written NFC (test with `café.txt`, `ünïcode`); read loop tolerates ARCHIVE_WARN |
| P2-33 | Compress PDF gains the D-PDF-2 pre-flight guard in 2A, and fit-to-size presets when the preset table (P2-131) lands in 2B | Forms/signatures/tags present → "Lossless only" preselected; preset targets land ≤ target on the PDF corpus or refuse before encoding |
| P2-39 | Split PDF via qpdf; sheet adds Every N, Ranges (`1-3, 7, 10-end`, reverse, `z`), Odd/Even | Range parser unit tests incl. out-of-range errors; 63 pages split every 4 → 16 files < 1 s; names `X Pages/X 001.pdf` |
| P2-41 | Extract covers every libarchive read format (zip, 7z, rar/rar5, tar + gz/bz2/xz/zst/lz4, gz, bz2, xz, zst, iso, cab, lha, cpio); smart single-top-folder; batch; password ZIP via P2-101 sheet | Fixtures per format extract; single top folder → no double nesting; encrypted RAR/7z → `unsupportedEncryption` copy naming The Unarchiver/Keka |
| P2-42 | **Create PDF becomes Combine into one PDF v1** (images + PDFs + SVG; see P2-120 row text below for full scope). ToolID `pdfFromImages` kept as a decode alias of `pdfCombine` | See P2-120 |
| P2-43 | Merge PDFs: **qpdf first** (primary-input rule), PDFKit only for thumbnails | Merged form fields stay live (`name`, `name+1`); 3 inputs merge < 0.1 s; outline of the first file kept |
| P2-49 | Trim Audio's auto-silence uses the shared keep-list model (P2-134) | Same keep list drives Trim ends and Remove Silences |
| P2-51 | EngineVision base also hosts the shared `TextRecognizer` and `VisionWarmup` (P2-103) | — |
| P2-55 | **Float shelf becomes the Drop Box panel** (states, dock, grid/list, QL, keyboard, AX) on top of P2-141; wheel label `BOX` (`tray.full`), `ActionID.pinFloating` raw value kept | Restored after relaunch; drag-out of 200 items works; missing → Attention state with Locate…; Trash path counts as missing |
| P2-61 | Splits into three public betas: P2-119 (0.5), P2-139 (0.6), P2-159 (0.7). P2-61 becomes the M5 exit check after 0.7 | M5 = all P2 rows incl. ≥ 100. [challenge] Retitle P2-61 and tag `v0.7.0-beta` (it currently tags `v0.5.0-beta`). 05 M5's "6 actions" becomes 9 (FR-93) |
| P3-24 | Warm-up moves to P2-103; P3-24 keeps faces / PII / tracking detection | — |
| P3-31 | CLI: the headless subset ships in P2-146 ([challenge]: was "P2-152", which is Remove Blank Pages); P3-31 completes `tool`, `tools`, `wheel`, `history`, `box`, P-CLI channel, cask, completions, Install CLI button; owner verbs in P3-108 | Exit codes 0/1/2/3/130 + 5 wrong password, 6 unsupported encryption, 7 verification failed |

---

### 9.2 Milestone additions (05 §2)

| Milestone | Definition | Tasks | Exit check |
|---|---|---|---|
| **M5a** | Public beta 0.5: owner priorities 1–3 (OCR, Office/ZIP/any-file lock, PDF lock/unlock/merge/split/compress) on top of the P2 platform | P2-01, P2-10, P2-12, P2-13, P2-19, P2-30, P2-31, P2-33, P2-39, P2-41, P2-43, P2-51, P2-100…P2-119 | Copy Text 12/12 Hindi+English fixtures ≤ 1 % CER; Office lock/unlock round-trips with Word/Excel/PowerPoint (LK-M1, LK-M2); AES ZIP opens in Archive Utility (LK-M4); PDF Lock output AES-256 verified, opens in Preview (ASCII password) |
| **M5b** | Public beta 0.6: images, multi-file top 3, share presets, silences | M5a + remaining P2 image/media tool rows + P2-120…P2-139 | Combine (images+PDF), Reel and Stitch golden tests; fit presets land ≤ target first try on corpus; silences A/V offset < 1 frame |
| **M5c / M5** | Public beta 0.7 = Phase 2 complete: documents, Drop Box + notch, wheels, history, archives, searchable PDF | All P2 rows | 05 M5 checks + P2-140…P2-159 green; size gate ≤ 85 MB hard, report vs 70 MB |

---

### 9.3 Phase 2, wave 2A — owner priorities 1–3 (→ beta 0.5)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P2-100 | Catalog visibility, cap and combining rule | Core, WheelCore | — | M | `ApplicabilityRow` marks each tool `defaultVisible` or `extra`; builder shows visible tools in catalog order capped at 12 for **every** list (tools, same-family conversions, actions); lint test fails if any default list > 12; mixed-family selections show combining tools whose accepted families cover all items (Combine PDF, Reel; Actions archive/lock); table tests over all inputs and 30 mixed sets **[TDD]** (can start during Phase 1) | FR-90, FR-91, FR-27; app §3.1 |
| P2-101 | Password sheet (Lock / Unlock / Change) | UI, Core | P2-30 | M | `SecureField` ×2 + eye, strength hint, **Suggest** via `SecCreateSharedWebCredentialPassword` + Copy; Unlock field shakes on wrong password, no attempt limit; NFC→NFD silent retry; batch "same password for all n" default on, failures re-listed in a second sheet; per-family notes (ZIP names visible, Office recipients, non-ASCII PDF warning); VoiceOver "Wrong password"; Return = Lock | FR-96; lock L-01 |
| P2-102 | Password policy and privacy tests | Tests, Runtime | P2-101 | S | Test password never appears in os_log capture, History JSON, crash-report fields, `UserDefaults`, argv or env of any child; passwords held as `[UInt8]`, zeroed after KDF (best effort); plaintext staging dir 0700, removed on cancel and at next launch; CI grep fails on any `--password ` argv construction | FR-96, NFR-21; lock L-08, LK-R5/R6 |
| P2-103 | OCR core: `TextRecognizer` + `VisionWarmup` in the worker | EngineVision | P2-01, P2-51 | M | `RecognizeDocumentsRequest` ([challenge]: it has no recognition level, per Vision.swiftinterface `TextRecognitionOptions` = minimumTextHeightFraction, automaticallyDetectLanguage, recognitionLanguages, useLanguageCorrection, customWords, maximumCandidateCount; `.accurate` exists only on `RecognizeTextRequest`, the fallback), languages ordered (Hindi first when hi/mr in user languages or Hindi keyboard enabled), auto-detect off by default; capability probe hides Hindi where no supported language has `languageCode == "hi"` ([challenge]: the Swift API reports `hi-Deva-IN`, VN reports `hi-IN`); all Vision calls run in `ZivletWorker` only (one process identity); warm-up at `.utility` after onboarding on 64 px and ~3000 px images for the production configs, "warmed for OS build X" flag, re-warm after OS update; determinate "Preparing text recognition (one time)…" state, never times out the job | FR-104, NFR-22; image §1, pdf F8 |
| P2-104 | Copy Text tool (images, then PDF pages) | EngineVision, UI | P2-103, P1-41 | M | Instant slice `COPY TEXT`; default → clipboard; result card text variant (first lines, char count, scripts, Copy again / Save as .txt / Show all); ⌥ writes `X Text.txt` (UTF-8, LF); multi → one combined text with `— name —` separators, ⌥ one .txt each; "No text found" is not an error; History stores "Text copied, n characters", never the text; CI fixture fails if any Devanagari golden returns no Devanagari. [challenge] PDF pages with a text layer that contains Devanagari go through OCR (PDFKit extraction is in visual order, 17a-pdf.md L1); Word- and Chrome-made Hindi PDF fixtures; clipboard `.currentHostOnly`; honour the PDF extract permission (OWN-PDF-5) | FR-105; image §1 |
| P2-105 | PDF pre-flight and verify | EnginePDF | P2-13 | M | `PDFPreflight` (qpdf `--json`): encryption, AcroForm, signature fields, StructTreeRoot, EmbeddedFiles, JavaScript, page count in ≤ 50 ms for 100-page files; `PDFVerify`: qpdf `--check` on every output + re-open with the expected reader; any PDFKit write is rewritten through qpdf | FR-107; pdf P2-13a/b |
| P2-106 | Lock / Unlock / Change password for PDF | EnginePDF | P2-101, P2-105 | M | qpdf R6 AESv3 via `qpdfjob` JSON (password never in argv); optional restrictions (print none/low/high, copy, edit) with random 24-char owner password shown once; Unlock with the owner password, or with the user password only when the file grants all permissions or user = owner (qpdf reports which matched) ([challenge]: otherwise `--decrypt` with the user password strips owner restrictions, a bypass under OWN-LK-1); restrictions-only files require the owner password; Change Password needs the owner password when restrictions exist; outputs `X Locked.pdf` / `X Unlocked.pdf`; verify `/Encrypt` R6; non-ASCII password warning + "check it opens on Mac" (PDFKit re-open) result; RC4/AES-128 never written; S-PDF-LOCK matrix recorded | FR-97; pdf F1/F2 |
| P2-107 | Encrypted PDF inputs in every PDF tool | EnginePDF, Runtime | P2-106 | S | One Unlock prompt per encrypted input per job, password kept in memory for that job only; outputs keep protection except Unlock ([challenge]: as is, via qpdf preserve-encryption, which may be RC4; upgraded to AES-256 only when the owner password is known; never owner = user); permission bits honoured per OWN-PDF-5; public-key/LiveCycle → `unsupportedEncryption` | FR-97, FR-101; pdf D-PDF-4 |
| P2-108 | `EngineOfficeCrypto`: CFB + Agile | EngineOfficeCrypto (new) | P2-01 | M | CFB reader/writer v3 (≤ 6 MB) and v4; Agile AES-256/SHA-512/100,000 spins read+write with dataIntegrity HMAC and full `\x06DataSpaces`; Standard (2007) read; IRM/certificate encryptors refused; round trips byte-identical vs msoffcrypto-tool oracle (dev-only venv) for docx/xlsx/pptx incl. a 38 MB DIFAT file; libFuzzer target over the CFB reader; 128 MB input cap; XML entities disabled **[TDD]**. [challenge] Size M → **L**: the spike (508 lines) proves the crypto, but CFB v3+v4 writing, DIFAT, Standard read, IRM detection and a fuzz harness to production quality are a week of work | FR-98; lock L-02 |
| P2-109 | Office Lock / Unlock / Change tools | EngineOfficeCrypto, Core | P2-101, P2-108 | S | Probe signatures (CFB + `EncryptionInfo`); docx/docm/dotx/xlsx/xlsm/xltx/xlsb/pptx/pptm/potx keep extension; `X Locked.docx`; 03b §9 rule changed (encrypted OOXML → `passwordRequired`, IRM still refused); manual LK-M1/LK-M2 pass before beta **[QA]** | FR-98; lock L-03 |
| P2-110 | ZIP passphrase plumbing | EngineArchive | P2-19 | M | Separate read/write passphrases; AES-256 (AE-1/AE-2) default; ZipCrypto only behind "compatible (weak)" toggle with ASCII-only passwords; Change Password in one pass; store heuristic for already-compressed types (UTI + 64 KB sample); progress; ZipCrypto CRC failure → `wrongPassword`; extraction limits apply to re-pack | FR-99; lock L-04 |
| P2-111 | Lock any file → AES-256 ZIP; Actions `LOCK` slice | EngineArchive, Actions, UI | P2-110, P2-113, P2-101 | S | Any file, folder or mixed drop → `X Locked.zip` / `n Files Locked.zip`; "As" picker: ZIP (default), Keep format (default for PDF/Office: native lock); one archive vs one per file; system bsdtar and pyzipper read the output; LK-M4 Archive Utility prompt **[QA]** (Archive Utility AES support is INFERRED from its linked libarchive, so LK-M4 is a beta gate) | FR-100, FR-93; lock L-06 |
| P2-112 | Unlock-then-convert (ZIP, PDF) | Runtime | P2-101, P2-106, P2-110 | S | A route whose probe reports `passwordRequired` shows the Unlock sheet before running; decrypted copy only in staging; card says "The converted file won't have a password." | FR-101; lock L-07 |
| P2-113 | libarchive NFC-on-write vendor patch | Vendor | P2-19 | S | Patch in `Vendor/patches/`, SPDX note; test: ZIP/7z header names are NFC for NFC and NFD inputs | FR-99; lock L-05 |
| P2-114 | Lock slot label refinement | WheelCore, Wheel | P2-100, P2-106, P2-109, P2-110 | S | One `tools.protect` slot per family; frame 1 shows the provisional label from type; label refines to LOCK / UNLOCK / "LOCK · UNLOCK k of n" from the ≤ 30 ms header probe within ≤ 100 ms p95 without moving any slot; [challenge] `CHANGE PASSWORD` is **not** a slice. A slice that appears only when every item is encrypted changes the frame-1 set (FR-18). It is a mode of the Unlock sheet. "k of n" uses the OWN-2 badge, because the label frame is 82 × 22 pt at 7.5 pt. The pre-drop probe skips dataless/iCloud and TCC-protected items (provisional label kept) | FR-92 |
| P2-119 | Public beta 0.5 | Release | M5a rows | S (+ ≈ 1 week of stabilisation, [challenge]) | M5a exit checks; O-12 name decision done (blocks any public artifact); `v0.5.0-beta` | M5a **[OWNER]** |

---

### 9.4 Phase 2, wave 2B — images, multi-file top 3, share presets, silences (→ beta 0.6)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P2-120 | Combine into one PDF v1 (= modified P2-42) | EnginePDF, UI | P2-42, P2-43, P2-105, P2-40 | L | Multi drop of images (+SVG) and PDFs → one PDF: images become pages (JPEG bytes embedded), PDFs appended via qpdf; **one bookmark per source file** (libqpdf outline shim); page size Fit / A4 / Letter; order Finder / name / date; optional review-order sheet with drag-to-reorder (Organize thumbnail grid); encrypted PDFs prompted (P2-107); names: images-only `<first> Images.pdf` (parity), PDFs-only `<first> Merged.pdf`, mixed `<first> Combined.pdf`; 50-file mixed golden | FR-118; picks ⭐1 |
| P2-121 | Photos + videos → Reel | EngineMedia, UI | P2-46, P2-133 | L | Stills N s each (default 3 s, Ken Burns off), clips kept with audio, optional music bed (loop/trim, fade, ducked under clip audio), crossfades (`xfade`/`acrossfade`, default 0.5 s), presets 16:9 1920×1080 / 9:16 1080×1920 / 1:1 1080×1080 with the P2-133 framing modes (crop / pad / blur-fill); VT H.264 + AAC, `+faststart`; `<first> Reel.mp4`; duration = Σ − crossfades ± 1 frame; A/V drift ≤ 1 frame; plays in QuickTime | FR-119; picks ⭐2 |
| P2-122 | Stitch images into one long image | EngineImage | P2-123 | M | Vertical (default) / horizontal; widths normalised to the narrowest (or widest, option) via the hybrid resampler; optional gap and background; ICC kept; PNG out for screenshots, JPEG/HEIC for photos (auto by content, option); output > 65,000 px on the long side splits into parts or switches to PNG with a warning; `<first> Stitched.png` | FR-120; picks ⭐3 |
| P2-123 | `ResizeSpec` + hybrid resampler + Resize tool | EngineImage, UI | P2-30 | M | Modes long edge (3840/2560/1920/1280/1080/800/custom), width, percent, fit-in-box; never upscale by default (card "skipped"); thumbnail decode ≥ 2× target then CI Lanczos; SSIMULACRA2 ≥ 90 vs linear Lanczos on the 4 CC0 photos; EXIF date/camera kept, orientation baked and reset, dimension tags updated, "Remove location" option; P3 kept unless "Web (sRGB)"; animated GIF/WebP all frames; `X Resized.ext`; Replace originals opt-in with Undo | FR-114; image §2 |
| P2-124 | Batch rename (`ZivletRename`) + Actions `RENAME` | ZivletRename (new), Actions, Runtime, UI | P1-15 | M | Tokens `{name} {counter:n@s} {date:fmt} {ext} {EXT}` + text; presets; sort as dropped / name / date taken / modified; live preview with date source per row; conflicts (in-batch duplicate, existing outside batch, invalid name, > 255 B) block Rename; NFC + case-folded keys; journal then two-phase rename (swaps, cycles, case-only); crash recovery at launch; Undo restores (skips changed inodes); capture time zone honoured; sidecars (AAE, XMP, RAW+JPEG, Live Photo MOV) renamed together by default **[TDD]** for planner. [challenge] Size M → **L**: journal, two-phase rename, crash recovery, sidecar grouping and per-volume name rules are each a day or more | FR-115; image §3 |
| P2-125 | Smaller PNG (extends P2-31) | EngineImage | P2-10, P2-31 | S | → PNG conversions get the oxipng preset-2 pass by default; Compress PNG: Lossless (default) / Smallest (imagequant + oxipng) offered only when quantisation quality ≥ 90 at min 80, else "This looks like a photo" + one-click convert; APNG never quantised; never bigger than input; oxipng cancellable via deadline | FR-116; image §4 |
| P2-126 | Remove Background (one tap) | EngineVision, EngineImage | P2-103 | S | `VNGenerateForegroundInstanceMaskRequest` behind `ForegroundMasker` (Swift request re-tested in I-V3); soft mask at full res; `X No Background.png` (HEIC/WebP keep format with alpha); option Crop to subject; "No subject found" not an error; card before/after on checkerboard + "Check edges" + Smaller PNG / Add background follow-ups | FR-106; image §6 |
| P2-127 | Images → animated GIF | EngineImage | P2-123 | S | Frame delay (default 0.5 s), width (480/960/1280), loop; palette via ffmpeg `palettegen`/`paletteuse` (or ImageIO GIF if I-C2 shows parity); optional animated WebP; `<first> Animation.gif`; frame count = inputs | FR-121 |
| P2-128 | Contact sheet | EnginePDF, EngineImage | P2-123 | S | Thumbnail grid (columns auto / 3–8) with file name captions, page size A4/Letter; PDF default, PNG option; images + video first frames + PDF first pages; `<first> Contact Sheet.pdf` | FR-122 |
| P2-129 | Join audio into one track | EngineMedia | P2-36 | M | Concat in drop/name order; optional crossfade (default off, 2 s); matched loudness (two-pass `loudnorm` to −16 LUFS default, option off); output format = first input's family, mixed → m4a; `<first> Joined.m4a`; duration within ±1 frame of expectation | FR-123; picks ⭐ |
| P2-130 | Batch semantics for owner tools | Core, Runtime | P2-100 | S | Convert, Compress, Resize, Rename, Fit for… accept multi drops; one result line "n of m saved · k skipped · k failed"; table test that each listed tool is `multiAllowed` | FR-124 |
| P2-131 | Preset table + `FIT FOR…` slice | Core, Wheel, UI | P2-32, P2-33, P2-196 (P-W5) | M | Versioned JSON (`limitBytes`, `safetyMargin` 3 %, `kind`, `verifiedOn`, source); defaults WhatsApp media 15.5 MB, Gmail 18 MB, Discord 19.4 MB (owner confirms 20 MB, OWN-MA-1); user presets in Settings; `FIT FOR…` opens a preset ring on dwell (if P2-196 passes) else drop opens a compact picker; "Already fits…" writes nothing; unreachable budget refused before encoding with the minimum size; `X WhatsApp.mp4` | FR-95; media-ai §2 (MA-04) |
| P2-132 | Image fit-to-size search | EngineImage | P2-131, P2-123 | M | Binary search on lossy quality (≤ 8 passes, 0.02 window), then long edge × 0.8 steps; WebP uses `target_size`; lands ≤ target on corpus in ≤ 6 passes median | FR-95; MA-05 |
| P2-133 | Instagram presets (inside FIT FOR…) | EngineMedia, EngineImage | P2-131 | S | Reel 9:16 1080×1920, Portrait 4:5 1080×1350, Square 1080×1080; Fill (crop) / Fit (pad) / Blur fill (¼-res blur, ≤ 1.5× pad time); H.264 High ≤ 60 fps, AAC 128k, `+faststart`, ~8 Mbit/s cap; > 3:00 note + optional "Trim to 3:00", never silent trim; `X Reel.mp4` / `X 4x5.jpg` | FR-126; MA-06 |
| P2-134 | Keep-list model + `silencedetect` parser + adaptive threshold | EngineMedia | P2-30 | S | Pure parser → keep list with padding; Auto threshold = p10 of 100 ms RMS + 6 dB clamped −60…−25 dB; lavfi sync fixture detects pauses to 0.1 ms **[TDD]** | FR-125; MA-01 |
| P2-135 | Remove Silences render + slice | EngineMedia, UI | P2-134, P2-49 | M | ≤ 40 segments trim/concat, > 40 frame-snapped `select`; VFR → trim/concat; 5–10 ms afade at joins; Natural (≥ 0.5 s, 0.15 s pad) / ⇧ Tight (≥ 0.3 s, 0.08 s); `X No Silences.ext`; "No long pauses found" writes nothing; tool window shading from P2-49 waveform; CI: 100-segment fixture end drift ≤ 25 ms, A/V offset < 1 frame | FR-125; MA-02, MA-03 |
| P2-139 | Public beta 0.6 | Release | M5b rows | S (+ ≈ 1 week of stabilisation, [challenge]) | M5b exit checks; `v0.6.0-beta` | M5b **[OWNER]** |

---

### 9.5 Phase 2, wave 2C — Drop Box + notch, wheels, history, archives, PDF pull-forwards (→ beta 0.7 = M5)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P2-140 | Size estimator protocol + tier 0 hot-slice label | Core, WheelCore, Wheel | P2-131, probe cache | M | `estimate(probe, settings) → {value, range, tier}` per engine; tier 0 computed from metadata only before the drop ([challenge]: file size, type, Spotlight pixel size/duration; no content reads, no ffprobe, no dataless download, no TCC-triggering reads during a drag) (≤ 5 ms per slice); hot slice second line "≈ 4.2 MB (−71 %)", "≤ 15.5 MB", "Already smaller", range for constant-quality video; read from cache only on highlight (≤ 1 frame); Settings toggle default on; local estimate-vs-actual log | FR-94; MA-07 |
| P2-141 | Drop Box core (`ZivletShelfCore`) + shake detector | ZivletShelfCore (new), Trigger | P1-44, P0-22 | M | Immutable `Shelf`/`ShelfItem` (bookmark `.withoutImplicitSecurityScope`, resolve with `.withoutImplicitStartAccessing`); de-dup by file identity; Trash path = missing; `boxes.json` 0600 atomic, schema-versioned; lazy resolve; owned copies only for promise/clipping content under `Box/<id>/`; auto-clear plans; shake detector 4 reversals ≥ 30 pt in 0.6 s (opt-in), 0 false positives on recorded non-shake traces **[TDD]** | FR-132; app P2-55a/d |
| P2-142 | Drop Box bulk actions | Actions, UI | P2-55, P1-45, P2-147 | M | Share (`NSSharingServicePicker`), AirDrop, Copy (URLs), Copy paths, Move to… / Copy to… (one undo entry), Zip via coordinator, Convert all (drag out with ⇧), Remove, Move to Trash (confirm > 1), Clear (10 s undo toast); per-item failure list; storage line + "Empty box storage" | FR-132; app P2-55c |
| P2-143 | Notch shelf | Actions, TriggerHost, Trigger | P2-141, P2-55 | L | During a file drag the pure `NotchProximity` detector (sampler data, no new permission) expands an island tray from the notch (`safeAreaInsets.top`, `auxiliaryTopLeftArea/RightArea`); drop stashes into the current box; hover/click opens the tray later; panel above the menu bar on all Spaces incl. full screen; non-notch displays get a top-centre pill; per-screen on externals; Reduce Motion → fade; never covers menu-bar items beyond the hover; works alongside the wheel (wheel drop wins when both are targets); P-N1 spike thresholds; 0 TCC prompts (TCC diff) **[QA][HW]** | FR-133; picks notch |
| P2-144 | Custom wheels v1 (`ZivletPresets`) | ZivletPresets (new), WheelCore, Wheel, UI | P1-46, P2-100 | M | `WheelLayout {mode, scope, order, hidden, accent, sliceColours}`; scope resolution format > family > default; hide/show, reorder, ≤ 12 shown, ≥ 1 per mode; new tools appended (badge); per-mode accent; RGB/contrast maths moved to WheelCore; Settings › Wheels list with live `WheelView` preview; keyboard-mode 1–9 follow order | FR-134; app P2-71 |
| P2-145 | History v1 (`HistoryLog`) | Runtime, UI | P1-15 | M | Evolves UndoLog; `history.json` 0600 atomic, excluded from backup; one-time migration of `undo.json`; retention Off / 7 / 30 (default) / 90 days, max 500; window with search, filter, Reveal, Undo (24 h, stamp-checked), Re-run (re-validates via throwing init; password tools re-ask), Re-run with…, Copy details, Remove, Clear; menu Recent shows 10; never stores passwords or OCR text | FR-135; app §4 |
| P2-146 | CLI headless subset | ZivletCLIKit (new), zivlet-cli | P2-01, P-PKG | M ([challenge]: was S; the JSON envelope, NDJSON progress, SIGINT process-group teardown, helper lookup and nightly-matrix wiring don't fit in a day) | `zivlet formats/info/convert` with JSON envelope `{schema, ok, data}`, NDJSON progress on stderr, exit 0/1/2/3/130 (ArgumentParser 64 → 2), SIGINT kills helper groups; helper lookup via `Bundle.main.executableURL` resolved; used by the nightly matrix | FR-136; app P2-73 |
| P2-147 | Archive creation (Actions `ZIP` + extras) | EngineArchive, Actions, UI | P2-19, P2-110, P2-100 | M | Actions slices `ZIP` (default visible), `7Z`, `TAR.GZ`, `TAR.XZ`, `TAR.ZST` (extras); options: level Fast/Normal/Smallest, one archive (default) vs one per item, AES password (ZIP), strip `.DS_Store`/`__MACOSX`/AppleDouble (default on); naming `Folder.zip` / `Archive.zip` / `name 2`; never RAR; job submitted through the ZivletUI coordinator (Actions imports no engine, R3) | FR-127, FR-93 |
| P2-148 | Peek inside an archive | EngineArchive, UI | P2-41 | M | Window lists entries (name, size, date, encrypted flag) without extracting; Quick Look of one entry via staging; extract selected; drag entries out; bomb/path limits enforced on preview; password prompt via P2-101 | FR-129 |
| P2-149 | Archive → archive conversion | EngineArchive, Core | P2-147 | M | Catalog pairs: inputs zip/7z/rar/tar/tgz/tbz2/txz/tzst/iso/cab/lha/cpio → zip, 7z, tar, tar.gz, tar.xz, tar.zst, tar.bz2 (streaming re-pack, no temp extraction for ≤ limits); RAR input only; encrypted inputs prompt; entries, folders, dates, permissions kept; symlinks kept as entries | FR-130 |
| P2-150 | Make Searchable PDF | EnginePDF, EngineVision | P2-103, P2-105 | M | Skip pages with usable text (≥ 20 printable chars, < 5 % U+FFFD); render 300 DPI; invisible text layer as logical-order glyphs at natural advances, placed per word from Vision boxes, quads for rotated text; original page untouched; Devanagari font per OWN-PDF-4; `X Searchable.pdf`; PDFKit `findString` finds 9/9 test words (Hindi + English); poppler CER 0.000 on fixture; cancellable progress, pages in parallel | FR-109; pdf F8 |
| P2-151 | Resize Pages v1 | EnginePDF | P2-105 | S | A4/Letter/Legal/A5/A3/custom; Fit (default) / Fill / Actual; auto-orient; Quartz redraw (images not re-encoded); pre-flight warns "Links and form fields will be flattened" (v2 lossless in P4-105); `X A4.pdf` | FR-111; pdf F7 |
| P2-152 | Remove Blank Pages | EnginePDF, UI | P2-105, P2-40 | M | Detector per 17a-pdf.md §3.6 (paper mode, ink > 64 levels, 0.8 mm speck rule, edge/hole-punch rules, blank < 0.002 %, nearly < 0.3 %); 15/15 labelled corpus; instant removes only "blank"; card "Removed n · k nearly blank kept" + Review… in the Organize grid; never removes pages with fields, links or signatures; Strict / Normal / Aggressive; `X Blank Pages Removed.pdf`; S-BLANK-1 before beta **[QA]** | FR-110; pdf F6 |
| P2-153 | Combine into one PDF v2 (Office and text inputs) | EnginePDF, EngineDocs | P2-120, P2-15, P2-17, P2-22, P2-21 | M | docx, xlsx/ods/csv, pptx, md, txt rendered to pages through the existing → PDF routes then merged; optional contents page; documents needing an optional engine (ppt) dimmed in the review sheet with reason | FR-118 |
| P2-159 | Public beta 0.7 (= M5) | Release | All P2 rows | S (+ ≈ 1 week of stabilisation, [challenge]) | 05 M5 exit checks (P2-61) + 2C rows green; size gate report | M5 **[OWNER]** |

---

### 9.6 Phase 3 additions (1.0)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P3-100 | PDF incremental-update writer (libqpdf shim) | EnginePDF | P2-105 | M | Appends objects + new xref; original bytes are an exact prefix (`cmp`); indirect `/Annots` resolved via object helpers; existing signatures still "valid" in `pdfsig` after a visual stamp when DocMDP allows; refuse when `/Perms` DocMDP = no changes | FR-112; pdf F9a |
| P3-101 | Visual signature: capture, store, place | EnginePDF, UI | P3-100, P2-126 | M | Draw (trackpad/mouse), type (system script fonts), import image (threshold or Vision mask); saved signatures in Keychain as data, `kSecAttrSynchronizable = false`, no sync option ([challenge]: iCloud Keychain is a cloud path); place/resize on any page, optional date and initials on every page; `X Signed.pdf`; copy "This is a visual signature. It doesn't prove who signed."; placement UI reused by P3-21 Annotate; usability test **[QA]** | FR-112; pdf F9a |
| P3-102 | JPEG XL output + JXL → original JPEG | Vendor, EngineImage | P2-01, size gate | M | libjxl 0.12 static (`SKCMS=ON`, tools off) wrapped as `ZivletJXL`; JPEG input → lossless transcode bit-exact (`cmp` after reconstruct) and 15–19 % smaller on corpus; others d1.0 (Balanced) / d2.0 (Compact) / lossless (High, graphics); EXIF/XMP/ICC boxes; first-use compatibility note; size delta ≤ 3.3 MB measured; shipped only if OWN-IMG-1 approves the size | FR-117; image §5 **[OWNER]** |
| P3-103 | Background subject picker (refine window) | EngineVision, UI | P2-126, P2-30 | M | Click to toggle instances (`instanceAtPoint` on the Swift `InstanceMaskObservation`; on the VN fallback, read `VNInstanceMaskObservation.instanceMask` at the point, [challenge]); edge decontamination option; 1 px erode for hard edges | FR-106 |
| P3-104 | Legacy Office unlock (.doc → .xls → .ppt) | EngineOfficeCrypto | P2-108, LK-M3 | L | RC4, RC4 CryptoAPI, XOR per MS-OFFCRYPTO; FIB flag / FILEPASS cleared; each format ships only when its fixture corpus (Word/Excel-made, LK-M3) opens without a prompt in Word/Pages/Numbers; never locks legacy formats (sheet offers convert to OOXML first) **[QA]** | FR-102; lock L-10 |
| P3-105 | Encrypted disk image option | EngineArchive | P2-111 | S | `hdiutil create -encryption AES-256 -stdinpass` (password via stdin only), verify by mounting `-nobrowse -readonly`, cleanup on cancel; `X Locked.dmg` | FR-100; lock L-09 |
| P3-106 | Unlock-then-convert for documents | EngineDocs, Runtime | P2-112, P2-108 | S | Encrypted docx/xlsx/pptx inputs to any document route prompt, decrypt in memory (≤ 128 MB) | FR-101; lock L-07 |
| P3-107 | Custom wheels v2 | ZivletPresets, UI | P2-144, P2-131 | M | Per-slice colours (12 swatches + custom picker) with automatic outline below 3:1 on light; built-in presets (Default, Minimal, Creator, Office & PDF); `.zivletwheel` import/export (256 KB cap, diff + confirm, issue list capped at 50, bad colours reported); `.preset` pinned slices | FR-134; app P3-50 |
| P3-108 | CLI owner verbs | zivlet-cli | P3-31, P2-106, P2-109, P2-110 | M | `lock/unlock/passwd` (TTY `readpassphrase` or `--password-stdin`, no `--password`), `pdf merge|split|compress|remove-blank|resize|ocr|sign-visual`, `archive create|extract|list|convert`, `text` (OCR), `resize`, `rename --pattern`, `fit --preset`, `insta`, `silence`, `combine`, `box add|list|clear`, `history`; exit 5/6/7 | FR-136 |
| P3-109 | Model-pack infrastructure | Runtime, UI | P2-01 | M | `engines.lock` pins URL, size, SHA-256; user-initiated HTTPS download to `Application Support/Zivlet/Packs/<name>/<ver>/`, verify then atomic rename; data-only packs (no code, keeps library validation); Settings › Engines lists/deletes packs; CI with network blocked still passes (packs absent → features hidden) | FR-137, NFR-23 |
| P3-110 | `AICapability` service + PCC ban | Core, EngineAI (new) | — | S | One service reports Foundation Models availability (eligible / AI off / not ready), locale support, Translation pack status; drives slice visibility and degraded copy; CI lint fails on any reference to `PrivateCloudComputeLanguageModel` | FR-137; MA-14 |
| P3-111 | **Transcription slot (reserved)** | per docs/design/16 | P2-01, P3-109 | — | Rows to be defined by `docs/design/16-transcription.md` (not yet written); reserved: `TRANSCRIBE` slice (audio/video, counted in caps), history kind `transcribe`, CLI verb `transcribe`, segment model with timestamps + language + Roman and Devanagari forms | FR-138 |
| P3-112 | Translate transcript → English | EngineAI, UI | P3-111, P3-110 | S | Translation framework `installedSource:target:` batches; Roman Hinglish passed as source hi; missing pack → `.translationTask` prompt in a window (CLI fails with a clear message); timestamps kept per line; `X English.srt|txt`; original kept beside | FR-139; MA-10 |
| P3-113 | 7-Zip helper gate (encrypted 7z) | Vendor, EngineArchive | P2-147 | M | If OWN-ARC-2 approves: `7zz` 26.x built **without RAR codecs**, signed helper, 7z AES read/write with header encryption; licence notices; size ≤ 3 MB; [challenge] password reaches `7zz` via pty/stdin, never `-p<pw>` on argv (NFR-21), or the row closes. If not approved: row closed | FR-131 **[OWNER]** |

---

### 9.7 Phase 4 additions (1.x)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| P4-100 | Speaker pack + diarisation + transcript merge | EngineAI | P3-109, P3-111, AI-S2 | L | CoreML data-only pack (≈ 16 MB, **unmeasured**) per AI-S2; [challenge] no sherpa-onnx shipped fallback (it is code: onnxruntime, ≈ 60 MB, fails the data-only rule), test baseline only; speakers Auto/2/3/4/5+; segment takes speaker with the largest overlap, split at turn boundaries when word times exist; DER ≤ 20 % on AI-S1 recordings | FR-140; MA-11 |
| P4-101 | Meeting Notes | EngineAI, UI | P4-100, P3-112 | M | Hindi/Hinglish translated first; token-budgeted map-reduce (`tokenCount`, macOS 26.4+, with a character-count fallback on 26.0–26.3 [challenge]; ~2,000-token chunks) into `MeetingSummary {keyPoints, decisions, actionItems}`; `X Meeting Notes.md` (+ docx option) with speaker-labelled transcript; rename/merge speakers rewrites the file; "AI-generated, check against the transcript" label; degraded path writes transcript only with the reason | FR-140; MA-12 |
| P4-102 | Ask in plain words | EngineAI, UI | P3-30, P3-110, P2-131 | M | Phrase table (EN, Roman Hinglish, Devanagari keywords) + FM guided generation into a registry-constrained `Plan`; validator drops impossible steps, unmentioned destinations, no-op converts, invented sizes; confirm card always; delete/send/upload refused with fixed copy; file names never passed as instructions; eval set of 100 requests ≥ 90 % correct, 0 destructive or networked steps | FR-141; MA-13 **[OWNER confirm]** |
| P4-103 | Size estimates tiers 1–2 | EngineImage, EngineMedia | P2-140 | M | Images: 36 native-res 256 px tiles, error ≤ ±10 %; video: k=3 sample encodes only in tool windows / keyboard mode, never during a drag | FR-94; MA-08 |
| P4-104 | Smart crop for presets | EngineMedia | P2-133 | M | Vision objectness saliency every 1 s, faces first; static crop unless subject moves > 20 % width; real-footage spike | FR-126; MA-09 |
| P4-105 | Resize Pages v2 (lossless) | EnginePDF | P2-151, P3-100 | M | Form-XObject placement keeps links and fields live; annotation rects transformed | FR-111 |
| P4-106 | Split by size / by bookmarks | EnginePDF | P2-39 | M | "Parts under 25 MB" (preset table) and top-level outline splits | FR-108 |
| P4-107 | Digital signature (PAdES B-B) | EnginePDF | P3-100, S-SIGN-1 | L | Keychain or CryptoTokenKit identity; own CMS (swift-asn1) with signing-certificate-v2, no signing-time attribute; "Signature is valid" in Acrobat with a test CA and EU DSS; no TSA by default | FR-113 **[OWNER gate]** |
| P4-108 | iWork lock/unlock via Apple Events | Runtime (AppleScript runner) | O-17 | M | Opt-in only; slices shown only when the app is installed; `saving in keychain false`; LK-M6 decides whether a GUI prompt appears | FR-103; lock L-12 |
| P4-109 | Edit-restriction removal with verified password | EngineOfficeCrypto | P2-108 | M | Only after verifying the typed password against the stored hash; never blind strip | FR-103; lock L-13 **[OWNER]** |
| P4-110 | Interactive background refine (macOS 27) | EngineVision, UI | P3-103 | M | `#available` tap/box/brush refinement; [challenge] `GenerateIterativeSegmentationRequest` is a `DownloadableAssetsRequest`, so assets come from Apple over the network: user-initiated download card, never automatic, named in the privacy copy | FR-106 |
| P4-111 | Shake-to-open on by default | Trigger | P2-141 | S | After recorded-trace QA shows 0 false positives in 500 normal drags | FR-132 |

---

### 9.8 Spikes and manual QA (run before the rows they gate)

| ID | Question / check | Gates | Size | Pass bar |
|---|---|---|---|---|
| P2-190 | I-V1/S-V1 extended ([challenge]: not a new I-V2): Hindi OCR on macOS 26.0/26.x; cold compile; cache across app update, reboot, app vs XPC | P2-103 | S | `hi-IN` listed; 12/12 ≤ 1 % CER with `[hi,en]`; first OCR after warm-up ≤ 3 s |
| P2-191 | S-OCR-HI: real Hindi scans and phone photos | P2-104, P2-150 | S | Median CER ≤ 0.05 at 300 DPI |
| P2-192 | S-PDF-LOCK interop matrix (Preview, Acrobat, Chrome, Edge, iOS/Android) | P2-106 | S | All open with ASCII passwords; non-ASCII results documented |
| P2-193 | LK-M1…LK-M5 lock manual QA (Word/Excel/PowerPoint, iWork, Archive Utility, Windows) | P2-109, P2-111 | S | 17b-lock.md §14 pass bars **[QA][OWNER]** |
| P2-194 | I-V3: Swift `GenerateForegroundInstanceMaskRequest` on 26.x | P2-126 | S | Works → switch back; else keep VN |
| P2-195 | I-R1 + I-C2: hybrid resize on 12–48 MP HEIC/RAW; idle oxipng/cjxl timings | P2-123, P2-125, P3-102 | S | SSIMULACRA2 ≥ 90; ≤ 0.3 s / 12 MP on idle M1 |
| P2-196 | P-W5: dwell-to-expand preset ring on the wheel | P2-131 | M | No hitch > 2 frames; dwell 350 ms usable in a moderated test (n ≥ 5); else picker fallback |
| P2-197 | P-N1: notch proximity and island panel; [challenge] also: TCC/iCloud behaviour of pre-drop reads (with P0-33) | P2-143, P2-114, P2-140 | M | Panel above menu bar in full screen on 26.x; drag-near-notch detection ≥ 95 % with 0 accidental opens over 200 recorded normal drags; no TCC prompt **[HW]** |
| P2-198 | S-BLANK-1: 300-page real scan set | P2-152 | S | 0 content pages classed blank; ≥ 95 % blanks caught |
| P2-199 | AI-S4/AI-S5: real-footage fit calibration; Gmail 18/24 MB and WhatsApp 15.5 MB real sends | P2-131, P2-140 | S | Preset targets confirmed **[OWNER]** |
| P3-190 | AI-S1/AI-S2: diarisation on real meetings; FluidAudio CoreML pack size + model licences | P4-100 | M | DER ≤ 20 % **with the CoreML route** (only sherpa-onnx is measured so far, [challenge]); data-only pack ≤ 20 MB; licences GPL-distributable, including the embedding model |
| P3-191 | AI-S3: Translation + FM throughput on idle M1 Air | P3-112, P4-101 | S | 1 h meeting translate + summarise ≤ 5 min |
| P3-192 | S-SIGN-1: Swift CMS → PAdES B-B | P4-107 | M | Valid under test CA in Acrobat and EU DSS |

---

### 9.9 Backlog moves (§7)

| Old | New | Note |
|---|---|---|
| B4-05 Remove Background | P2-126 (one tap), P3-103, P4-110 | 0 MB, owner pick |
| B4-06 Make PDF Searchable | P2-150 | owner pick, PDF suite marked important |
| B4-07 PDF Protect, Unlock | P2-106; Optimize/Fast Web View stay B4-07 | |
| B4-09 Batch Rename | P2-124 | |
| B4-10 JPEG XL output | P3-102 (size-gated); jpegli stays B4 | |
| B4-12 7z/AES-ZIP creation, extra inputs | P2-110, P2-147, P2-148, P2-149, P2-41 | |
| B4-15 Presets, fit-under-size, hover estimates | P2-131…133, P2-140 (tier 0), P4-103 | Discord preset 20 MB, not 10 |
| B4-16 Customisable wheels | P2-144, P3-107 | |
| B5-03 Transcribe → SRT/VTT | P3-111 slot (owned by 16-transcription.md) | |
| B5-04 Foundation Models "describe what you want" | P4-102 | |

New owner dependencies for §8: OWN-PDF-1…4, OWN-LK-1, OWN-ARC-1/2, OWN-APP-1…6, OWN-IMG-1, OWN-MA-1…5
(listed in 17-feature-roadmap §14); manual QA P2-193 needs Microsoft Office for Mac and a Windows 11 VM.

---

### 9.10 Effort tally (ESTIMATE; S = 1 d, M = 3 d, L = 7.5 d)

| Block | Rows | S / M / L | Engineer-days | Weeks (5 d) |
|---|---|---|---|---|
| Wave 2A | P2-100…114, P2-119 + growth of P2-33/39/43 | 11 S / 8 M / 0 L | 35 | ≈ 7 |
| Wave 2B | P2-120…135, P2-139 | 8 S / 7 M / 2 L | 44 | ≈ 9 |
| Wave 2C | P2-140…153, P2-159 | 3 S / 11 M / 1 L | 43.5 | ≈ 9 |
| Phase 2 spikes | P2-190…199 | 8 S / 2 M | 14 | ≈ 3 |
| Phase 3 additions | P3-100…113 (excl. slot) + P3-190…192 | 5 S / 10 M / 1 L | 42.5 | ≈ 8.5 |
| Phase 4 additions | P4-100…111 | 1 S / 9 M / 2 L | 43 | ≈ 8.5 |

Phase 2 grows by about **27 weeks** (136.5 engineer-days) on top of its original 8–10 weeks (one engineer). That is why 17-feature-roadmap
§4 splits Phase 2 into three public betas and keeps the owner's top priorities in the first one. Transcription
(P3-111) is not counted here.

> [challenge] **Corrected reading of this tally.**
> - On the same S/M/L convention, 05's original 47 Phase 2 rows are **156 days (≈ 31 weeks)**, not 8–10 weeks, so
>   Phase 2 roughly **doubles**.
> - With the re-sizes above (P2-108 M→L, P2-124 M→L, P2-146 S→M: +11 d) and three beta stabilisations (+15 d), the
>   additions come to **≈ 163 days + 14 spike days**.
> - Using 10 §12's calendar ratio, that is about **+9–11 calendar weeks**.
> - Use these numbers for relative sizing only. M1–M3 were built in days by agents.

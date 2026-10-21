# 07 — Plan critique (critic3)

Date: 2026-10-20. Scope: 01-prd, 02-architecture, 03 / 03a / 03b, 04-tech-doc, 05-task-list, 06 / 06a–06f, checked against
00-decisions and the design docs 10–15. Every in-place edit carries the tag `[critic3]`.

## 1. Method

| Check | How |
|---|---|
| Consistency | grep of every count, ID, module name, default and timing across the plan docs |
| Fidelity | Each wheel, trigger, media and image number traced to a documented source (design docs 10–14) |
| Feasibility | Ran on the dev Mac in a scratch directory (local prototype, not published): `swift package init`, a tools-6.2 probe manifest, a full M1 replay, `make app / test / coverage / lint` |
| M1 executability | Script matched every Swift block in 06a–06f to the M1 reference package (local prototype, not published). All test files and all "complete" sources match verbatim. The 11 non-matching blocks are outlines, the Task 2 manifest and `ZivletApp.swift`, as intended |
| Legal | Searched for strings, assets and code-port instructions copied from the reference app |

## 2. Verified, no change needed

| Item | Result |
|---|---|
| Toolchain | macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4 (6.4.0.34.1), XcodeGen 2.45.4, git 2.54.0, ffmpeg 8.1.2. All match 04 §1.1 |
| Manifest | `swift package init` writes `swift-tools-version: 6.4`. The plan's 6.2 works: `.macOS(.v26)`, `.defaultIsolation(MainActor.self)`, `.treatAllWarnings(as: .error)`, `NonisolatedNonsendingByDefault` and Swift Testing all build and pass (probe). `swift build --show-bin-path` = `.build/out/Products/Debug`, as 04 §6.8 says |
| M1 replay (before edits) | 24 + 28 + 1 + 33 + 16 = 102 tests passed. Coverage: Core 98 %, Trigger 100 %, WheelCore 99 %, EngineMedia 95 % |
| App | Fresh `make app`: `** BUILD SUCCEEDED **`, `flags=0x10002(adhoc,runtime)`, `LSUIElement` true, id `app.zivlet.Zivlet`, min OS 26.0 |
| Counts | 275 = 49+8+56+42+6+9+65+6+21+4+9 everywhere. 46 formats = 45 in / 39 out. 27 tools, 6 actions. Phases 153 / +68 = 221 / +54 = 275. 19 tools at P2. 5 actions at P1 (Float at P2) |
| Wheel numbers (03a, 06d) | 372 panel, 42.24 / 48.64 / 119.52 / 125.92, gap via `asin(min(2/r,0.95))`, label r 84.53, intro 50.4, 0.07 s fade, 0.20 s intro curve: consistent with Zivlet's wheel spec in 03a §2 |
| Media ladders (03b, 06e) | Balanced values match 11 §10 / 10 §4.4–4.5 (VT q 60, VP9 crf 32, mp3 q:a 2, m4a 192k, ogg q 6, opus 128k, wma 192k). Compact and High come from 11's option lists (VT 48/72 from 11 §9). GIF 15 fps / 480 px / sierra2_4a / 50 MB guard from 11 §10.3. Image 0.65/0.85/0.96, WebP 65/85/96 and the 360×108 HUD are Zivlet's own spec values (03a, 03b) |

## 3. Findings and fixes

| # | Sev | Location | Issue | Fix applied |
|---|---|---|---|---|
| 1 | HIGH | 06c Task 6, 06 D4, 02 §7.6, 03a §1.5, 03b §8.1 vs 01-prd FR-4 / D-3, 05 D-3 / P0-23, 04 §6.5, 14 §1.3 | M1 defaulted `honorsModifierHeldAtDragStart = true` (parity). That fails the P1 acceptance test FR-4, and with ⌘ bound to Tools every Finder ⌘-move drag would open the Tools wheel. 03a cited 02 for parity; 14 §1.3, the original source, says ignore | Default is now `false` in the 06c outline and table. Tests: "ignored by default", new "opens once released and pressed again", "parity when on". Re-verified: Trigger 29/29, lint clean, Trigger coverage 100 %. 02, 03, 03a, 03b and 06 D4 updated; 05 D-3 renamed to the real field |
| 2 | HIGH | 01-prd §5.5, §5.6, D-8; 05 P0-25 | Two hit models disagreed with 03a, 05 P0-24 and M1. The PRD used rounded radii 42/48/120/126, a 320 pt panel and slack to r 148, none of them matching the wheel spec. P0-25 used slack to "2 × ring radius", a 120 ms time hysteresis (from 14 §2.2) and a `.gap` result | PRD now uses 42.24 / 48.64 / 119.52 / 125.92, 372 pt panel, slack to r 150, 3° (03a §2.4). P0-25 now uses r 150, 3° and no `.gap` |
| 3 | HIGH (legal) | 06d 7c `EmptyReason.message`; 03a §2.6; 05 P0-15; 03b §5.6 and §7 | About ten empty-state, pill, action-error and video-track error strings matched the reference app's wording verbatim in an early draft, which broke the clean-room copy rule in 01-prd line 15 and 04 §5.1 | All replaced with Zivlet's own copy (06 D15). 06d test and source re-verified: WheelCore 24/24, lint clean. PRD §5.10 note: never reuse the reference app's copy |
| 4 | HIGH | 01-prd FR-24 (P1) | "Hub offset ≤ 64 pt with all labels on-screen" cannot be met by the fixed P1 layout: labels sit up to ~126 pt from the hub, and 03a §2.1 shifts the disk by up to 134 pt | P1 criterion: disk + 8 pt margin inside `visibleFrame` (offset ≤ 134 pt at a corner). P3 target (≤ 8 pt after P-W3) kept |
| 5 | MED | 01-prd FR-20, 05 D-1 / P0-15 / B4-14, 02 §7.1 vs 03a §2.6 + M1 Task 7 | Mixed-family selection: the PRD, 05 and 02 said intersection or empty; 03a and M1 build a badged union (≤ 12 slots) | Upstream docs aligned to the implemented union; B4-14 folded in. **[OWNER]** confirm at the P-W1 usability pass (06 D5) |
| 6 | MED | 01-prd D-21, §6.2 rows 2 and 16, B-22 vs 05 D-4, 03a §4.4, M1 Task 5 | The PRD promised consistent names ("No Metadata", "Speed 2x"). The plan and code use the parity names ("Metadata Removed/Edited" for images, "Speed 2.0x"). O-16 lists no naming change | PRD set to parity, D-21 marked deferred. **[OWNER]** add it to O-16 if wanted |
| 7 | MED | 03a §4 HUD / Reveal, 03b §8.1 vs 01-prd §5.8 | Success card 1.5 s vs 4 s (hover holds). Reveal default off vs on | Aligned to the PRD: 4 s is enough time to reach Undo; reveal on (parity). **[OWNER]** may choose off |
| 8 | MED | 01-prd §5.4 | Unsourced or conflicting timings: "opaque first frame + 180 ms spring", tick ≥ 30 ms, watchdog "armed/live" | Aligned to 03a §2.7 / §1.5: 70 ms fade + 200 ms intro, 35 ms tick spacing with a 150 ms stale cut-off, watchdog only in pressed/passive |
| 9 | MED | 01-prd FR-4 | "Edge at +20 ms ignored". M1 defers early edges to the 40 ms mark and fires only if the mask still matches | FR-4 acceptance text matches the M1 semantics |
| 10 | MED | 02 §7.6 | Stale contract: fixed `lingerAfterExit` (03 had already changed it to `releaseTimeout` 150 ms); `show(at: CGPoint)` vs M1 `Point2D` | Fields renamed. §7.7 note: pure modules use `Point2D` (06 D2) |
| 11 | MED | 05 P0-02, P0-10; 04 §4.1 | P0-02 lacked `ZivletWheelCore` and used `.macOS("26.0")`. P0-10 called gz output-only (gz is also an input; 06 D7). 04 §4.1 lacked WheelCore | Rows corrected; WheelCore added to 04 §4.1 with an 80 % gate |
| 12 | MED | 05 phase headers | Phase estimates sum to 32–43 weeks, against the 10 §12 [challenge] estimate of 12–18 months (O-18) used in 01-prd §10 | Note added: the estimates are effort floors |
| 13 | MED (legal hygiene) | 02, 04, 05 | Error type `SatsumaError` has the same name as an Open-Tangerine internal type (00-decisions O-12 note) | Renamed `JobError` / `JobErrorConvertible` in all plan docs |
| 14 | LOW | 06a, 06c, 06e verify commands | `grep -E "…|error"` also matched Swift Testing's `error →` argument labels (noisy output) | Pattern changed to `error:` |
| 15 | LOW | 06f §9.3 | `make app` prints "Disabling hardened runtime with ad-hoc codesigning". Readers may think the runtime flag is missing | Note added: `OTHER_CODE_SIGN_FLAGS` still sets it (verified `0x10002`) |
| 16 | LOW | 02 §4.2 R1 vs 04 §4.1 | Import allowlists differed (`Synchronization` vs `os`) | Both list Foundation, UTType, Synchronization, os |
| 17 | LOW | 04 §1.1 | Dangling reference §9.3 | Pointed to §9.1 |
| 18 | LOW | 05 §2 M1 | The milestone said "coverage on Wheel geometry" and did not reflect 06's two-step M1 | Gated modules listed; the 06 §2.1 follow-on rows referenced |
| 19 | LOW | 06 index §1, Task table; 06f exit check | Counts changed by fix 1 | 103 functions / 729 cases; Trigger 29; exit total 103 |

## 4. Not changed (noted)

| Sev | Location | Note |
|---|---|---|
| LOW | 06 §4 vs 05 §1.5 | Nesting ≤ 3 vs ≤ 4. 06 is stricter, so no conflict in practice |
| LOW | 06 §4, CONTRIBUTING | Commits use `<type>(<scope>): …`; the owner rule reads `<type>: <description>`. Scopes are valid conventional commits. Drop them if the owner wants the exact form |
| LOW | 03b §5.4 | Zivlet's audio defaults (e.g. mp3 VBR V2) differ from the reference app's behaviour. This is not in the O-16 or PRD D-list of behaviour changes. Consider listing it |
| LOW (legal) | 03a §2.6 hub labels, 06b tool petal labels | Short functional labels (`MIXED`, `"<n> <TYPE> FILES"`, `SNAPSHOT`, `READ QR`) are generic functional words but may resemble the reference app's labels; an owner check against prior art is cheap |
| INFO | 06a Task 1 | Needs network (`curl` GPL text). The hash is pinned |

## 5. Open issues for the owner

| # | Decision | Default now in the docs |
|---|---|---|
| OWN-1 | Held-modifier behaviour (finding 1) | Ignore until re-pressed; parity available as a setting |
| OWN-2 | Mixed-family union with "k of n" badges (finding 5) | Union if ≤ 12 slots; confirm at P-W1 |
| OWN-3 | Consistent tool names (finding 6) | Parity names; adding them to O-16 enables the consistent set |
| OWN-4 | Reveal in Finder default (finding 7) | On |
| OWN-5 | Ratify the PRD D-1…D-22 behaviour changes. O-16 covers only conversion defaults and keys, not re-tap close (D-2), leave grace (D-6), hit model (D-8), etc. | As written in 01-prd §5.11 |
| OWN-6 | 06 D14: which docs are published | Only design and plan docs; they stand alone |
| OWN-7 | CI toolchain: hosted `macos-26` ships Xcode 26.6 (04 H-1). The M1 code is verified only on Swift 6.4 | Self-hosted runner or wait for an Xcode 27 image |

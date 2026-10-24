# 15 — Notch design pass: record

Date: 2026-10-24. Status: **tasks D0–D20 of [plan 14](14-implementation-plan-notch-design.md) committed on the local
branch `notch-design`; not merged, not pushed**. Every gate and exit row passes except **X6 (idle CPU)**: on a busy
Mac the progress row and the new glass pill row sit around the 1 % limit on both builds, and on the Debug app they
failed in all four exit runs (+1.11 % to +1.32 %). **G-M5a-1 is not closed** (§3). The owner has not yet reviewed the
screenshots of every state (OWN-UI-1, OS-2) or run Q27–Q32 ([qa/notch.md](qa/notch.md)), so the branch is not ready to
merge.

This is a record, not a plan. The design is [design/19b](../design/19b-notch-look.md), the owner decision OWN-UI-1 in
[00-decisions](../design/00-decisions.md). This file says what was built, the gate and CPU numbers with the load on
the Mac, the contrast readings, the decisions and deviations added while building, what was not measured or not seen,
and the owner steps.

Clean-room rule: unchanged. No code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch
or shelf app. Every new string is Zivlet's own.

---

## 1. What was built

| Task | What | Commit |
|---|---|---|
| D0 | Baseline: `make test lint` 1133 tests; Debug X6 progress +1.383 % (fail), the other states pass | none (no commit by design) |
| D1 | `make notch-idle CONFIG=release` builds its own optimised app with `ZIVLET_ISLAND_PREVIEW`; `release-check` refuses a shipped binary with the preview flag | `89fdeeb` |
| D2 | `VisibleProgress` (steps per drawn pixel) and `VisibleKey` (what the island draws or speaks) | `82d0096` |
| D3 | `NotchHUD.show` stops a snapshot whose key equals the drawn one | `9e5b5cc` |
| D4 | The spoken value lives in `IslandAccessibilityModel`, so it no longer re-evaluates the chrome | `831a5fa` |
| D5 | Debug and Release measured after D2–D4 (§3); step 4 was not triggered | none (no code change) |
| D6 | `IslandFinish`: black, glass or solid per surface, display and setting | `57022ef` |
| D7 | `IslandLook` (surface tokens) and `NotchLook` (content tokens); contrast over any surface in `NotchInk` | `5fe0d7d` |
| D8 | The 6 pt flare at the top corners; radii tab 12, toast 18, card 24 | `9fc8799` |
| D9 | `IslandFinishView`: glass with a 0.5 scrim and the black band, solid grey under Reduce Transparency and Increase Contrast, the outline; dark panel | `5fcd728` |
| D10 | `NotchIconButton`: symbols with today's titles as tooltips and labels | `016b954` |
| D11 | The tab shows the target's family symbol; done actions show the check mark | `79ccf61` |
| D12 | Toasts in two styles on one line (`NotchToastLine`) | `86ac782` |
| D13 | `NotchWorkingCard`: two rows; short time left (*new*) | `8bd60bd` |
| D14 | `NotchResultCard`: the name once, actions as symbols | `8819d99` |
| D15 | `NotchFailureCard` and `NotchActionCard` | `21fdfd6` |
| D16 | One line per list row with a short status ("Failed" *new*) | `114f054` |
| D17 | Content grows in with the shape (scale 0.96 and fade), fades only under Reduce Motion | `fe35c89` |
| D18 | `make notch-states`: every state captured, contrast checked over white; preview states and debug-only screenshot flags | `0d49bd8` |
| D19 | QA rows Q27–Q32, Q12 and Q25 updated; cross-references in 19 and 19b | `9209973` |
| D20 | Two new X6 rows (still glass card, glass pill with progress); three exit runs; this record | `a82a770`, this commit |

Fixes found by looking at the screenshots or the profile (each with its own test):

| Commit | What the screenshot or profile showed | Fix |
|---|---|---|
| `4438f45` | The failure toast cut the reason and kept the name whole | the primary line outranks a secondary line that gives way |
| `be4ac9f` | The failed list row cut its reason in the middle beside "Failed" | the row names the file; the reason stays on the card and in the spoken list |
| `deadfce` | The failure card's buttons on their own row left a tall empty band | buttons beside the text (71 → 51 pt without insets) |
| `b49d072` | A card in the pill sat 8 pt from the top, 12 pt from the bottom | 12 pt at the top when there is no housing |
| `9f5ca1d` | Profile of X6 progress on Debug: the tab redrew and the spoken value was pushed at every percent | the tab redraws at the ring's visible step (84 a turn) |
| `1f7c010` | The final failure card wrapped its reason after three words: the button row's spacer took half the row | the text has layout priority over the buttons |

## 2. Gates and exit rows (2026-10-24, run C, macOS 27.0, Xcode 27, M2 Pro 14-inch, at `1f7c010`)

| Row | Result | Numbers |
|---|---|---|
| X1 | pass | `make test lint coverage app release-check licence-gate`: 1215 tests; coverage (lines) ZivletCore 98 %, ZivletTrigger 100 %, ZivletWheelCore 99 %, ZivletEngineKit 97 %, EngineMedia 97 %, EngineImage 95 %, ZivletRuntime 95 %, ZivletTriggerHost 92 %, ZivletWheel 96 %, ZivletActions 91 %, ZivletSettings 96 %, ZivletUI 94 %, **ZivletNotchCore 98 %, ZivletNotch 96 %**; the Release build has no Homebrew path and no island preview; size and licence gates OK |
| script-test | pass | every `Scripts/tests/test-*.sh`, the new `test-notch-states.sh` and the extended `test-notch-idle.sh` included |
| X2 | pass | failed once inside run C (56 ms against 50 ms, load average about 10); passed alone right after (load 3) and in runs A and B |
| X3 | pass | heic → jpg at the notch: island lines and `build/m5a-exit/notch-toast.png` |
| X4 | pass | the same demo near the drop: no island line |
| X5 | pass | no tccd request with `preflight=no` |
| X6 | **fail** | §3 |
| X7 | pass | signed off, no `Co-Authored-By`, no file ≥ 800 lines, no personal path |
| notch-states | pass | 28 images in `build/notch-states/`; the four contrast rows of §4 pass |

Runs A (at `a82a770`) and B (at `9f5ca1d`) gave the same X1, X3–X5 and X7 results; the code after them changes only the
tab's redraw rule (`9f5ca1d`) and the failure and action cards' layout (`1f7c010`).

## 3. Idle CPU (X6, G-M5a-1) on Debug and Release

CPU of the app, 120 s per state after 10 s to settle, minus the baseline ("Near the drop", no job). Every number was
taken on the owner's Mac while it did other work; the load average is given for each run. Between runs on the same
code a state moved by up to about 0.4 % (M5a's record saw the same).

| State (limit over baseline) | D0 `49cb038` | D5 `831a5fa` | run A `a82a770` | run B `9f5ca1d` | run C `1f7c010` |
|---|---|---|---|---|---|
| **Debug** load average start → end | 3.88 → 3.05 | 3.24 → 2.60 | 7.72 → 1.82 | 13.63 → 1.23 | 10.23 → 2.98 |
| baseline | 0.000 % | 0.050 % | 0.008 % | 0.008 % | 0.042 % |
| hidden (0.1 %) | +0.008 % | +0.050 % | +0.025 % | −0.008 % | −0.009 % |
| collapsed, still (0.1 %) | +0.000 % | +0.375 % **fail** (alone right after: about +0.03 %, main thread idle) | +0.067 % | +0.000 % | +0.000 % |
| progress at 10 Hz (1 %) | +1.383 % **fail** | +0.983 % | +1.200 % **fail** | +1.159 % **fail** | +1.208 % **fail** |
| stepped glyph (1 %) | +0.825 % | +0.800 % | +0.817 % | +0.809 % | +0.816 % |
| card open, still, glass (0.1 %) | — | — | +0.000 % | −0.008 % | +0.000 % |
| pill with progress, glass (1 %) | — | — | +1.267 % **fail** | +1.209 % **fail** | +1.108 % **fail** |
| **Release** load average start → end | — | 16.45 → 4.06 | 2.13 → 1.66 | 1.65 → 1.48 | 4.07 → 7.47 |
| baseline | — | 0.033 % | 0.008 % | 0.000 % | 0.017 % |
| hidden (0.1 %) | — | +0.009 % | +0.000 % | +0.008 % | +0.125 % **fail** |
| collapsed, still (0.1 %) | — | +0.100 % | +0.000 % | +0.000 % | +0.050 % |
| progress at 10 Hz (1 %) | — | +0.742 % | +0.884 % | +0.825 % | +1.108 % **fail** |
| stepped glyph (1 %) | — | +0.584 % | +0.650 % | +0.633 % | +0.916 % |
| card open, still, glass (0.1 %) | — | — | −0.008 % | +0.000 % | −0.009 % |
| pill with progress, glass (1 %) | — | — | +0.934 % | +1.133 % **fail** | +0.966 % |

D0 and D5 had only the five M5a states. D5's Release build overlapped with a test compile of mine (load 16 at its
start); the measurement itself did not. Run C's Release "hidden" row draws nothing at all, so its +0.125 % is the Mac,
not the island: that is the size of the noise at load 4–7.

Run D (2026-10-25, at `a0cc215`, no code change since run C) repeated every gate on the committed state: `make test
lint coverage app release-check licence-gate script-test` passed (1215 tests, the same coverage), exit rows X2–X5 and X7
passed, `make notch-states` took the 28 images and the four contrast rows gave the values of §4 again. X6:

| State (limit over baseline) | Debug, load 5.74 → 8.26 | Release, load 8.12 → 6.54 |
|---|---|---|
| baseline | 0.058 % | 0.017 % |
| hidden (0.1 %) | −0.050 % | −0.017 % |
| collapsed, still (0.1 %) | −0.050 % | −0.009 % |
| progress at 10 Hz (1 %) | +1.242 % **fail** | +0.900 % |
| stepped glyph (1 %) | +0.750 % | +0.691 % |
| card open, still, glass (0.1 %) | −0.050 % | +0.000 % |
| pill with progress, glass (1 %) | +1.317 % **fail** | +0.916 % |

Every Release row passed in run D; the Debug progress rows failed again. Both runs were on a busy Mac, so neither is an
idle-Mac reading.

What this says:

- D2–D4 took progress on Debug from +1.383 % to +0.983 % with M5a's views. The look (glass, the 16 pt ring, the new
  views) costs about 0.15–0.2 % on top, so progress is back over 1 % on Debug (+1.16 % to +1.21 % in three runs, all
  on a loaded Mac). On Release it passed twice (+0.88 %, +0.83 %) and failed once at load 4–7 (+1.11 %).
- The still glass card costs nothing measurable (≤ 0.008 %). Glass that changes, the pill with progress, costs about
  as much as the black tab with progress, and sits on the 1 % line on Release.
- The preview's own driver builds a snapshot on the main thread ten times a second (19b §6.1); a real job's
  snapshots come from `ProgressSink`. These rows are an upper bound for real jobs, and they were never taken on an
  idle Mac.

Ways to close G-M5a-1, each the owner's call because each changes a rule of 19b §6.2 or the X6 limits:

1. Fewer ring steps for the tab and the pill (one per point, 42 a turn, instead of one per pixel): about half the
   redraws during a job.
2. Do not push a new spoken value between drawn changes while neither VoiceOver nor Switch Control runs (push it when
   one starts and at every surface change): one SwiftUI update fewer per redraw.
3. Measure X6 on an idle Mac (no Spotlight or Photos analysis), or gate X6 on the Release build only, as the shipped
   app is optimised.

Profile of the progress preview (20 s `sample`, main thread busy samples of about 15,000):

| When | Debug | Release |
|---|---|---|
| D5 (after D2–D4, before the look) | 146 (`NotchHUD.show` about 43, window layout 15, Core Animation commit about 29) | 112 (layout 17, commit about 31, `show` about 8) |
| D20 run A (with the look, before `9f5ca1d`) | 185 (SwiftUI graph update 43, `show` 30, layout 16, commit 16, spoken value 11) | not sampled |

D5 step 4 (empty `sizingOptions` on the measurer, a fixed tab frame) was not tried: the measurer is never in a window,
and the island's hosting view already has empty `sizingOptions`; the layout pass follows SwiftUI's invalidations, so
the change made was to cause fewer of them (`9f5ca1d`).

WindowServer's CPU over the same windows was not recorded (19b §6.3 asked for it for information only).

## 4. Contrast over a white backdrop (D18)

`make notch-states` with `-ZivletIslandBackdrop white` reads the lightest linear luminance in a text-free box of the
built island and computes white text at 0.8 over it (sRGB compositing, as `NotchInk`). Limit 4.5:1.

| Surface over white | Glass luminance in the box | White 0.8 text | Result |
|---|---|---|---|
| Saved toast on the notch (`notch-savedToast-white.png`) | 0.087 | 5.62:1 | pass |
| Pill, collapsed (`pill-collapsed-white.png`) | 0.102 | 5.13:1 | pass |
| Pill, saved toast (`pill-savedToast-white.png`) | 0.102 | 5.13:1 | pass |
| Result card on the notch (`notch-result-white.png`) | 0.060 | 6.82:1 | pass |

The same four values came out in all three runs; they match the probe's 0.102 for the smallest surfaces (19b §4.2
P7).

Over black (`notch-result-black.png`) the glass is near black; it was captured, not measured.

## 5. Decisions and deviations

| # | Plan said | Done | Why |
|---|---|---|---|
| DV1 | D6: `.black` without an outline; the outline from `outlined` | `.black(outline:)` carries it | Increase Contrast outlines the tab too, and the value says so in one place |
| DV2 | D9: a `DisplayOptions` protocol with a workspace adapter and a change stream; `IslandHosts(finishOverride:)` | the app reads the two settings and hands them to `IslandHosts.finishSettingsChanged`, which passes them to every host; the debug override uses the same call | one entry point, no new protocol; tests drive it directly |
| DV3 | D10: read the button's label from the accessibility tree in a test | the test checks the titles the button uses | SwiftUI builds no accessibility tree without an assistive client; Voice Control stays QA row Q30 |
| DV4 | D7: a token enum named `Type` | `NotchLook.TypeStyle` | `Type` cannot name a member in Swift |
| DV5 | D13: content width | fixed 336 pt (380 − 2 × 6 flare − 2 × 16) for the card and the list, centred on the pill too | the measurer and the views agree on one width |
| DV6 | D14 | a partly failed batch stays on the result card (thumbnail, Reveal), whose first line keeps the model's title | the failure card has no thumbnail; the partial result has saved files |
| DV7 | D15: Show Details toggles `chevron.down` to `chevron.up` | `chevron.down` only | Show Details disappears once the details show (M5a); there is no hide press |
| DV8 | D16: the row's title | a failed row names the file beside "Failed" | seen on screen (§1) |
| DV9 | D17: content leaves in 0.12 s ease-out | it leaves with opacity inside the surface's animation | one animation per surface change; the springs are unchanged |
| DV10 | D18: states `list`, `actionToast`, `failureToast` | also `savedToast`; `list` opens; a `-ZivletIslandReduceMotion YES` debug flag | the saved toast is the contrast row; the list only shows when open; the owner's Reduce Motion setting stays untouched |
| DV11 | D18: test first | `demo-notch-states.sh` was written before its shell test | recorded in its commit |
| DV12 | D18: the Reduce Motion capture mid-transition | captured after the cross-fade | the log line that starts the capture arrives later than the 0.18 s fade |
| DV13 | D20: a still-toast X6 row | not added; a still glass card row instead | a toast lingers 4 s by design (D-N11), so no toast stays for 120 s |
| DV14 | D20 | the screenshot flags also compile in the CPU measurement build | otherwise the Release pill row would measure the notch tab |

## 6. Known gaps (not measured, not seen)

- Glass on macOS 26.x: everything here ran on macOS 27.0 (Xcode 27, M2 Pro 14-inch).
- X6 on an idle Mac: every CPU number here was taken with other work running (§3).
- The real Reduce Transparency and Increase Contrast settings were not switched (they are the owner's); the solid and
  outlined finishes were seen through the debug flag only (Q12).
- Reduce Motion was seen through the debug flag only, and not mid-fade (DV12).
- A light, translucent menu bar next to the black band was not seen: the menu bar was dark in every screenshot (Q28).
- **Window content behind the glass shows through.** Under the pill's result card a terminal's title, and in the
  last run a blue button with its label, were visible behind the second line (`pill-result-glass.png`). The
  white-panel contrast check cannot see this. The scrim is one token (0.5, 19b D-NL2); raising it, or using the
  solid finish for the pill's card, is the owner's call (Q27). The notch's own toasts and cards were not affected in
  these screenshots: their band and the dark menu bar sat behind them.
- 120 Hz smoothness of the flare, the glass and the content transition was not judged (screenshots only).
- WindowServer's share of the glass was not measured.
- Voice Control "click Undo" and the focus ring of the icon buttons were not tried (Q30).
- The open points of plan 14 §6 are unanswered: (a) icon-only Undo and Retry, (b) the family symbol in the tab, (c)
  "Saved" as the toast's first word. The build follows 19b's choices (symbols with tooltips; family symbol; "Saved").

## 7. Owner steps

| # | Step |
|---|---|
| OS-1 | Answer plan 14 §6 (a)–(c) |
| OS-2 | Review the screenshots of every state: run `make notch-states` (they go to `build/notch-states/`, not tracked) |
| OS-3 | Run Q27–Q32 and the open M5a rows Q1–Q26 on real hardware |
| OS-4 | Merge `notch-design` into `main` and push when satisfied (the assistant never pushes) |

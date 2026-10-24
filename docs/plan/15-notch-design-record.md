# 15 — Notch design pass: record

Date: 2026-10-24, design review 2026-10-25 (§8). Status: **tasks D0–D20 of
[plan 14](14-implementation-plan-notch-design.md) and the design review's fixes committed on the local branch
`notch-design`; not merged, not pushed**. Every gate and exit row passed in runs A–E except **X6 (idle CPU)**: on a busy
Mac the progress row and the new glass pill row sit around the 1 % limit on both builds, and on the Debug app they
failed in all five exit runs (+1.08 % to +1.32 %) (§3). **G-M5a-1 is open** (§3, §8.3): plan 14 closes it only when
progress passes on both builds. The review's fixes were not measured for CPU and their new screenshots were not taken,
because the Mac's screen was locked and its display asleep for the whole review run (§8.3). The owner has not yet
reviewed the screenshots of every state (OWN-UI-1, OS-2) or run Q27–Q38 ([qa/notch.md](qa/notch.md)), so the branch is
not ready to merge.

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
| `c70cdad` | Profile of X6 progress on Debug after `9f5ca1d`: a new percent the ring cannot draw left the published key behind, so every snapshot until the ring's next step ran a full board transition that drew nothing | a snapshot also stops when the last applied board has its key and no step held back by the 250 ms floor waits (replaced by one rule with a wake-up in `7d70d4f`, §8); its CPU effect is not demonstrated (§3) |

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

Run E (2026-10-25, at `c70cdad`, the commit above): `make test` (1217 tests), `lint`, `coverage` (the same module
values as run C), `app`, `release-check`, `licence-gate` and `script-test` passed; X2–X5 and X7 passed; `make
notch-states` took the 28 images again with the same four contrast values. The first `make test` and `make coverage`
of this run failed three timing tests outside the island (`WheelControllerTests` twice, `SystemAdapterTests` once) at
load average 15–21; both passed when repeated at load 9–20. X6:

| State (limit over baseline) | Debug, load 7.75 → 3.35 | Release, load 9.48 → 3.88 | alone afterwards, load 3.6 → 4.4 |
|---|---|---|---|
| baseline | 0.008 % | 0.008 % | Debug 0.008 %, Release 0.017 % |
| hidden (0.1 %) | −0.008 % | +0.000 % | — |
| collapsed, still (0.1 %) | +0.000 % | +0.209 % **fail** | Release −0.017 % |
| progress at 10 Hz (1 %) | +1.184 % **fail** | +0.825 % | Debug +1.092 % **fail** |
| stepped glyph (1 %) | +0.742 % | +0.642 % | — |
| card open, still, glass (0.1 %) | +0.017 % | +0.000 % | — |
| pill with progress, glass (1 %) | +1.075 % **fail** | +0.842 % | Debug +1.134 % **fail** |

Release's still "collapsed" row draws nothing; alone right after it read −0.017 %, so its +0.209 % was the Mac (as run
C's Release "hidden"). Two single 20 s `sample` runs, one before and one at `c70cdad`, counted 159 and 131 busy
main-thread samples (of about 13,500, load about 8). That is one unrepeated sample each, taken at different load; it is
not evidence that `c70cdad` lowered CPU. The whole-app Debug number (+1.242 % in run D, +1.184 % in run E) moved by
less than the ±0.4 % run-to-run noise above. The main thread alone is still busy about 1 % of the time on Debug, which
is roughly the whole margin over the baseline.

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
| run E, before `c70cdad` (of 13,385) | 159 (preview driver task 72 of which `show` 62, SwiftUI graph update 34, window layout 15) | not sampled |
| run E, at `c70cdad` (of 13,581) | 131 (preview driver task 53 of which `show` 43, including the spoken value 7, SwiftUI graph update 44, window layout 15) | not sampled |

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
| DV5 | D13: content width | first a fixed 336 pt (380 − 2 × 6 flare − 2 × 16) for the card and the list, on the pill too; since the review (`03a6925`) 348 pt on the pill, which has no flare | the fixed width put the pill's content 22 pt from its sides, off the grid |
| DV6 | D14 | a partly failed batch stays on the result card (thumbnail, Reveal), whose first line keeps the model's title | the failure card has no thumbnail; the partial result has saved files |
| DV7 | D15: Show Details toggles `chevron.down` to `chevron.up` | `chevron.down` only; 19b §3.3 now says so (`557d633`) | Show Details disappears once the details show (M5a); there is no hide press |
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
- ~~The open working card and the list follow the ring's step, not every percent~~: fixed in the review (`7d70d4f`,
  §8); not yet seen on screen (Q37).
- 120 Hz smoothness of the flare, the glass and the content transition was not judged (screenshots only).
- WindowServer's share of the glass was not measured; since `638bfd7` X6 prints it beside every row, but no X6 run
  has happened since (§8.3).
- Voice Control "click Undo" and the focus ring of the icon buttons were not tried (Q30).
- The open points of plan 14 §6 are unanswered: (a) icon-only Undo and Retry, (b) the family symbol in the tab, (c)
  "Saved" as the toast's first word. The build follows 19b's choices (symbols with tooltips; family symbol; "Saved").

## 8. Design review (2026-10-25)

A review of the branch at `83da6f3` returned 26 findings (swift, look, perf and failure lenses). Each was checked
against the code before it was changed; every behaviour change has a test that failed first. Commits on
`notch-design`, after `83da6f3`:

| Commit | What |
|---|---|
| `23b1f5b` | A cancelled batch (every job cancelled: nothing saved, nothing failed) gets the stop glyph `stop.circle.fill` and Close in its toast, card and list row; before, the card showed the failure triangle while the toast showed the saved check mark, and the row offered Reveal and Open with no file. The card is picked from `BatchPresentation`'s phase, which `ResultCardModel` now carries; "Saved …" comes from the phase, not from the buttons |
| `a261ea5` | The shape is one closed contour (the lips joined to the body by a union), and the Increase Contrast outline is its own shape: one line inside the edge, open along the screen edge on a notch display |
| `03a6925` | The pill's card and list sit 16 pt from the body's sides (348 pt wide, was 336 with a 22 pt margin); the pill's tab uses the 12 pt inset; whether content hangs under a housing comes from the host's own display (`NotchHUD.hasHousing`, logged when the host is missing); `provider` is private again; the card inset is one token (`IslandLook.cardInset`) |
| `82a0359` | Tests that only restated a token are gone or check a relation |
| `657bb0c` | A new Reduce Transparency or Increase Contrast setting changes a shown island at once (a card can stay open until closed); the buttons' resting circle follows the island's outlined finish (an environment value), so the forced screenshot finish and the real setting match |
| `d703023` | The result card measures its second line with the font it draws it in (tabular digits, one `NSFont` token) and keeps a 2 pt margin |
| `7d70d4f` | One redraw rule for the tab and the open card (19b §6.2): the board knows which displays are open, an open card follows its own percent, bar and time left at most every 250 ms, a change held back by the floor has a deadline, `NotchHUD.show` drops a snapshot when the latest applied board has its key, and the key is worked out once per snapshot in one pass over the items |
| `557d633` | Cancel is `stop.fill` (it sat beside Close's X in the list); decorative symbols are hidden from VoiceOver; the bar is a `ProgressView` to VoiceOver; 19b §3.3 updated (the cancelled glyph, Cancel, Show Details disappears) |
| `4451234` | A refused screenshot flag is logged in public (the flag's name only) and fails the capture; yes/no flags take YES or NO only; `png-luminance.swift` refuses a bad `POINT_WIDTH` or a box not wholly inside the image |
| `313dd93` | Preview states and captures for the rest of 19b §5 (three jobs, failed tab, done tab, action card, failure with details, unknown-length card, three files with a note; pill tab with three jobs, pill list, pill result under Increase Contrast) and a fast progress state |
| `638bfd7` | X6 rows for fast progress (2 % a tick, about 17 ring steps a second, so the floor holds steps back) and for the solid pill with the same progress; WindowServer's CPU printed beside every row |

### 8.1 Findings

| # | Finding | Result |
|---|---|---|
| R1 | (swift, medium) a cancelled batch went to the failure card; toast and card disagreed | fixed `23b1f5b` |
| R2 | (swift, medium) two update paths: the open card followed the ring's step | fixed `7d70d4f` |
| R3 | (swift, medium) `buttonsFitBeside` measured with another font, no margin | fixed `d703023`, measuring kept: `ViewThatFits` over the card would also compare the primary line's full ideal width, which truncates by design |
| R4 | (swift, low) a new finish setting waited for the next surface | fixed `657bb0c` |
| R5 | (swift, low) `Radius.inner` hard-coded the card inset | fixed `03a6925` |
| R6 | (swift, low) `provider` widened to internal | fixed `03a6925` |
| R7 | (swift, low) tests restating constants; a misnamed 250 ms test | fixed `82a0359` |
| R8 | (look, medium) the outline drew a seam per lip and a line along the screen edge | fixed `a261ea5`; the new contrast screenshot was not taken (§8.3) |
| R9 | (look, medium) pill content 22 pt from its sides | fixed `03a6925`; not yet seen on screen |
| R10 | (look, medium) states missing from the preview and the captures | fixed `313dd93`, QA row Q33; the new pictures were not taken (§8.3) |
| R11 | (look, low) button circle followed SwiftUI's contrast, not the forced finish | fixed `657bb0c` |
| R12 | (look, low) monospaced digits under-measured | fixed `d703023` (same as R3) |
| R13 | (look, low) decorative symbols read by VoiceOver; the bar had no value | fixed `557d633`; no automated test (SwiftUI builds no accessibility tree without an assistive client, DV3); Q38 |
| R14 | (look, low) Cancel and Close both an X | fixed `557d633` |
| R15 | (look, low) Show Details has no hide state; spec and build disagreed | fixed in 19b §3.3 (`557d633`): the button disappears, as M5a |
| R16 | (look, low) the pill's tab used the 8 pt inset | fixed `03a6925` |
| R17 | (perf, medium) the record must not claim G-M5a-1 fixed or cite 159 → 131 as a CPU fix | fixed in this record (status, §1, §3): G-M5a-1 open, the sample called unrepeated; no A/B runs were made |
| R18 | (perf, medium) the gate did little for fast jobs; no wake-up for a held step | fixed `7d70d4f`; fast-progress row added `638bfd7`, not yet measured (§8.3) |
| R19 | (perf, low) `VisibleKey` built arrays and ran twice per snapshot | fixed `7d70d4f`; a many-file X6 row was not added: each row costs 130 s per build, and the key no longer allocates; the cost of a drop of hundreds of files stays unmeasured |
| R20 | (perf, low) WindowServer's share of glass not recorded | script fixed `638bfd7` (column plus a solid pill row); not yet measured (§8.3) |
| R21 | (perf, low) the progress row measures the preview driver, not a real `ProgressSink` job | skipped: a real job reaches `NotchHUD.show` the same way, at most 10 Hz on the main thread (`ProgressSink` throttles; `ConversionWiring.present` calls `show` and `menu.track`), and only the snapshot's construction happens off the main thread; a real-job row needs a two-minute conversion fixture. Judging X6 on Release only stays the owner's call (§3, option 3) |
| R22 | (failure, medium) the same as R4, with a test flipping the setting while a card is open | fixed `657bb0c` |
| R23 | (failure, low) a missing display silently meant "under a housing" | fixed `03a6925`: the host's display, logged when missing |
| R24 | (failure, low) a refused flag reset every flag silently; "yes" meant NO | fixed `4451234`; the capture script's log check has no shell test (it needs the app and the unified log) |
| R25 | (failure, low) `png-luminance` clamped a misplaced box, read a bad point width as scale 1 | fixed `4451234` |
| R26 | (failure, low) success inferred from the buttons; an action card's empty title | first part fixed `23b1f5b`; second skipped: every `ActionResult` that reaches the island has a toast or a card (`.cancelled` returns before the board), so the empty fallback cannot be drawn |

### 8.2 Decisions added

| # | Decision | Why |
|---|---|---|
| DV15 | `IslandClient.surfaceChanged(_:display:)` with a default empty implementation; the host calls it before asking for the new surface's content | the board needs to know the island is open to follow the open card; the client brings the card up to date before it is drawn |
| DV16 | The cancelled glyph `stop.circle.fill`, Cancel `stop.fill` | the stop shape says what happened and what the button does; neither is the dismissal X |
| DV17 | The demo presses Show Details before it opens the failure card | the capture crops the first frame after the surface, so the card has to be measured with its details |

### 8.3 Gates (2026-10-25, at `638bfd7`, macOS 27.0, Xcode 27, M2 Pro 14-inch)

The Mac's screen was **locked and its display asleep** for the whole run (`CGSessionCopyCurrentDictionary`
`CGSSessionScreenIsLocked = 1`, `CGDisplayIsAsleep = 1`), and the load average rose from about 9 to 47 (other work on
the Mac). Nothing that needs drawn frames could be measured or captured.

| Gate | Result |
|---|---|
| `make test` | 1240 tests; 3 failed, all outside the island and all waiting for drawn frames: `WheelControllerTests.theFirstFrameEndsTheTriggerToFrameSignpost`, `WheelControllerTests.hideFadesOutAndResets` (they failed again alone) and `SystemAdapterTests.samplerDeliversFramesUntilStopped`. No wheel or trigger source changed on this branch since `83da6f3`; with the display asleep no frame arrives. Not re-run with the screen awake |
| `make lint` | pass (swift-format strict, log privacy) |
| `make coverage` | the script stops on the three failures above; the same tests with only those three skipped (`swift test --enable-code-coverage --skip …`), then the script's report: ZivletCore 98 %, ZivletTrigger 100 %, ZivletWheelCore 99 %, ZivletEngineKit 97 %, EngineMedia 97 %, EngineImage 95 %, ZivletRuntime 95 %, ZivletTriggerHost 88 % (92 % in run C; the skipped frame test covers part of it), ZivletWheel 95 %, ZivletActions 91 %, ZivletSettings 96 %, ZivletUI 94 %, ZivletNotchCore 98 %, ZivletNotch 95 %; every module ≥ 80 % |
| `make app` | pass (Debug build succeeded) |
| `make release-check` | pass (no Homebrew path, no island preview, size OK) |
| `make licence-gate` | pass (13 components) |
| `make script-test` | pass (including the extended `test-notch-states.sh` and `test-notch-idle.sh`) |
| X1 | the gates above |
| X2–X5 | **not run**: X2's 50 ms timing at load 47 and X3's screenshot need an awake, unlocked screen |
| X6 (`make notch-idle`, Debug and Release) | **not run**: with the display asleep the island draws nothing, so the numbers would read low and mean nothing. The review's CPU effect (R2, R18, R19) is unmeasured; the last measured values are run E's (§3): Debug progress +1.184 % (fail), Release +0.825 % (pass) |
| `make notch-states` | **not run** (locked screen); the screenshots of the review's changes (R8, R9, R10, R14, R16, the cancelled glyph) were not taken |
| X7 | see the commit that adds this section |

G-M5a-1 stays **open**: progress failed on Debug in every measured run, and the review's redraw change has not been
measured yet.

## 7. Owner steps

| # | Step |
|---|---|
| OS-1 | Answer plan 14 §6 (a)–(c) |
| OS-2 | Review the screenshots of every state: run `make notch-states` with the screen awake (they go to `build/notch-states/`, not tracked); the review's new states are listed in Q33 |
| OS-5 | With the Mac awake and quiet, run `make test`, `Scripts/m5a-exit.sh --only X2,X3,X4,X5,X6` and `make notch-idle CONFIG=release`, then fill in §8.3 (the review's CPU numbers, WindowServer, the fast-progress and solid-pill rows) |
| OS-3 | Run Q27–Q38 and the open M5a rows Q1–Q26 on real hardware |
| OS-4 | Merge `notch-design` into `main` and push when satisfied (the assistant never pushes) |

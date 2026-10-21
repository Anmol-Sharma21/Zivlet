# 03 — Zivlet system design (index)

Date: 2026-10-20. Detailed design of each subsystem as Zivlet builds it. Split in two files to stay under the 800-line
ceiling. Module names and contracts come from [02-architecture](02-architecture.md); engine choices from
[10-tech-strategy](../design/10-tech-strategy.md); behaviour targets from [01-prd](01-prd.md) (observable behaviour only; nothing copied).

| § | Subsystem | File | Key decisions |
|---|---|---|---|
| 1 | Trigger | [03a §1](03a-system-design-interaction.md#1-trigger) | Pure `TriggerMachine` + AppKit `DragSampler`; event-woken, display-rate sampling; 19-row transition table; press-edge exact match; re-tap closes; 150 ms event-driven release |
| 2 | Wheel | [03a §2](03a-system-design-interaction.md#2-wheel) | Pre-warmed 372 pt panel; Zivlet geometry spec (48.64 / 119.52 / 125.92, gap 4, label r 84.53); sector hit-test with 150 pt slack and 3° hysteresis; data-driven slice lists |
| 3 | Catalog and routing | [03a §3](03a-system-design-interaction.md#3-catalog-and-routing) | 46-format registry; 4 KB signature sniffing at admission; 275-route literal table; ordered engines + capability gates |
| 4 | Job runtime | [03a §4](03a-system-design-interaction.md#4-job-runtime-zivletruntime) | 11 lanes; same-volume staging; `renamex_np(RENAME_EXCL)`; " 2" collisions; parity tool suffixes; 10 Hz monotonic progress; undo with identity check; orphan reaper |
| 5 | Media engine | [03b §5](03b-system-design-engines.md#5-media-engine-enginemedia) | `MediaInfo` model; fixed-order argv; per-stream copy with playability predicate; full audio/video/GIF matrix with Compact/Balanced/High ladders; goldens |
| 6 | Image engine | [03b §6](03b-system-design-engines.md#6-image-engine-engineimage) | ImageIO/Core Image pipeline; quality 0.65/0.85/0.96; libwebp 65/85/96; compress search; SVG and PDF raster rules |
| 7 | Actions | [03b §7](03b-system-design-engines.md#7-actions-zivletactions-app-process-no-engine) | AirDrop, Float, Copy, Move, Copy Path, Terminal; success toasts; non-modal errors |
| 8 | Shell | [03b §8](03b-system-design-engines.md#8-settings-onboarding-menu-bar-launch-at-login) | Typed `SettingsStore` with defaults table; 7-page resumable onboarding; AppKit menu; `SMAppService` state map |
| 9 | Security | [03b §9](03b-system-design-engines.md#9-security-hardening-unsandboxed-app-untrusted-inputs) | Worker isolation, helper signature checks, ffmpeg input confinement, quarantine propagation, archive/XML limits |

## Changes to sibling docs

| Doc | Field | Was | Now | Why |
|---|---|---|---|---|
| 02 §7.6 | `TriggerConfig.lingerAfterExit` | fixed linger | 150 ms `releaseTimeout`, used only when the button is released inside the wheel | Event-driven completion |
| 02 §7.6 | `InputSample`, `DragSummary` | — | add `source: SampleSource`, `acceptedModes` | Machine needs mouse-event kind and per-mode verdict without importing `Catalog` |
| 02 §7.7 | `HitResult.gap` | returned in gaps | never produced by the standard geometry | Gaps belong to the nearer slot |
| 02 §7.1 | `Route` | 4 fields | + `fallbackOnFailure`, `options` | Execute-time fallbacks and per-output settings |
| 02 §7.6 | `honorsModifierHeldAtDragStart` | true (parity) | **false** [critic3] | 01-prd FR-4 / D-3: a ⌘-move drag in Finder must not open the Tools wheel; parity stays available as a setting |

## Values introduced here (tune in the named spike)

| Value | Where | Spike |
|---|---|---|
| Detection window 300 ms; payload probe ≤ 8 ms for ≤ 512 items | 03a §1.5 | P-T1, P-T4 |
| Reject pill 1.2 s; shake 0.24 s; drop pulse 0.10 s | 03a §1.5, §2.7 | P-W1 |
| Union-with-badges for mixed families (≤ 12 slots) | 03a §2.6 | P-W1 usability pass |
| 9,999 collision attempts; 255-byte name truncation; undo retention 20 batches / 24 h | 03a §4.3–4.7 | unit tests |
| VP9 CRF 37/32/27; AVI/WMV `-q:v` 5/3/2 | 03b §5.5 | M-3 |
| TIFF LZW default; PDF page size from image DPI | 03b §6.2 | pair matrix |

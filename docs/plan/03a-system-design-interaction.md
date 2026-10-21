# 03a — System design, part 1: trigger, wheel, catalog, job runtime

Date: 2026-10-20. Part 1 of 2 ([index](03-system-design.md), [part 2](03b-system-design-engines.md)).
Builds on [02-architecture](02-architecture.md) (module names, contracts). Where this doc changes a 02 default, the row says so.

**Citation keys.** `[10 §8.5]` = design/10-tech-strategy. `[11]`, `[13]`, `[14]`, `[15 C-n]` = design docs 11/13/14/15.
`[01-prd …]` = the PRD. `[D00]` = design/00-decisions. `[spec]` = a Zivlet design value fixed by this plan (parity values
are stated as Zivlet's own spec). `[new]` = a Zivlet value chosen here; the named spike tunes it. No code, assets or copy
from the reference app are reused.

---

## 1. Trigger

### 1.1 Split: pure machine vs AppKit host

| Component | Module | Isolation | Job |
|---|---|---|---|
| `TriggerMachine` | `ZivletTrigger` | nonisolated value type, no clock, no AppKit | `step(event) -> TriggerStep {next, effects}` [02 §7.6]. All decisions below. |
| `DragSampler` | `ZivletTriggerHost` | `@MainActor` | Mouse monitors, display link, pasteboard reads; turns OS signals into `InputSample`s; executes effects |
| `DragPayloadProbe` | `ZivletTriggerHost` | `@concurrent` | Reads drag-pasteboard URLs once per `changeCount`, builds `DragSummary` (formats, folders, accepted modes) |
| `EscapeHotkey` | `ZivletTriggerHost` | `@MainActor` | Opt-in Esc: Carbon hotkey registered only while the wheel is visible (spike P-T3) [15 C-20] |
| Trace codec | `ZivletTrigger` | pure | JSON traces of `[TriggerEvent]` → expected `[TriggerEffect]`; golden tests [10 §8.10] |

Extensions to 02 §7.6 (additive): `InputSample.source: SampleSource {mouseDown, mouseDragged, mouseUp, frame, flagsChanged}`;
`DragSummary.acceptedModes: Set<WheelMode>` (computed by the host from `Catalog`, so the machine never imports it).

### 1.2 Inputs read per sample

| Input | API | Notes |
|---|---|---|
| Modifiers | `NSEvent.modifierFlags ∩ {⇧,⌃,⌥,⌘}` → `ModifierMask` | Caps Lock, Fn, numpad dropped (only the four modifier bits are kept) [spec] |
| Primary button | `NSEvent.pressedMouseButtons & 1` | Also the missed-mouse-up watchdog [14 §1.3] |
| Drag change count | `NSPasteboard(name: .drag).changeCount` | Monotonic; compared with `!=` [spec] |
| File-drag test | `availableType(from: [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes)` | Types only; runs once per count change [14 §1.3] |
| Location | `NSEvent.mouseLocation` (global, y-up) | Anchor for `show` |
| Pointer inside wheel | `WheelDropView` entered/exited flag | Set by drag enter/exit callbacks [spec] |
| Uptime | `ContinuousClock` → `Duration` | Machine has no clock of its own [02 §6.1] |

Never read: key codes (except opt-in Esc), keystrokes, window contents. No modifier logging
[01-prd NFR-6].

### 1.3 States

| State | Meaning | Sampler | Monitors installed |
|---|---|---|---|
| `idle` | Button up | off | global + local `leftMouseDown` |
| `pressed(snap, held, t0)` | Button down; `snap` = drag count at mouse-down; `held` = mods at mouse-down | off | + `leftMouseDragged`, `leftMouseUp` |
| `detecting(snap, held, deadline)` | First drag event seen; waiting for the count to move | on | dragged monitor removed [15 C-20] |
| `passive` | Non-file drag, or detection window expired | off; 2 Hz button watchdog | `leftMouseUp` |
| `live(cc, summary?, prev, queued?)` | File drag, no wheel. `summary` nil while the probe runs | on | `leftMouseUp` |
| `wheel(mode, cc, summary, prev, anchor)` | Wheel visible | on | `leftMouseUp` |
| `releasing(mode, deadline)` | Button released while the wheel is up; waiting for AppKit to finish the drop | on | — |

### 1.4 Transitions (complete; anything not listed is a no-op)

`edge` = `mods & ~prev ≠ ∅` (a key newly pressed; `prev` = mods of the previous sample). `match` = the binding whose mask **equals** `mods` exactly.
`prev` starts as `held` when `honorsModifierHeldAtDragStart` is false, else as `∅` (so held keys count as a press).

| # | From | Event / guard | To | Effects |
|---|---|---|---|---|
| T1 | idle | sample(mouseDown) | pressed(cc, mods, t) | install dragged + up monitors |
| T2 | pressed | sample(mouseDragged) | detecting(deadline = t + 300 ms) | removeDragMonitor, startSampler |
| T3 | pressed, detecting, passive, live | button up (event or watchdog) | idle | stopSampler, remove monitors |
| T4 | detecting | `cc ≠ snap` ∧ file types present | live(cc, nil) | probePayload(cc) |
| T5 | detecting | `t ≥ deadline` | passive | stopSampler |
| T6 | live(summary nil) | edge ∧ match | live(queued = match) | — (applied by T7) |
| T7 | live | payload(cc) arrives | live(summary) | if queued: as T8/T9 |
| T8 | live(summary) | (edge ∧ match = m ∧ m ∈ accepted), and `t − liveStart ≥ edgeDebounce` | wheel(m, anchor = location) | show(m, at: location) |
| T9 | live(summary) | edge ∧ match = m ∧ m ∉ accepted | wheel(m) | show(m); the `WheelModel` renders the empty-state pill and refuses drops |
| T10 | wheel(m) | edge ∧ match = m ∧ `retapClosesWheel` | live | hide(sameModifierRetap) |
| T11 | wheel(m) | edge ∧ match = m2 ≠ m ∧ m2 ∈ accepted | wheel(m2) | switchTo(m2) (in-place morph) |
| T12 | wheel(m) | edge ∧ match = m2 ∉ accepted | wheel(m) | reject(m2, reason): shake + pill 1.2 s |
| T13 | wheel(m) | edge ∧ no match (e.g. ⇧⌘ unbound) | wheel(m) | — |
| T14 | wheel(m) | button up ∧ pointer outside wheel | idle | hide(buttonUp), stopSampler (release elsewhere: no linger) |
| T15 | wheel(m) | button up ∧ pointer inside wheel | releasing(m, t + releaseTimeout) | — (AppKit is delivering the drop) |
| T16 | releasing | `dropHandled`, or `t ≥ deadline` | idle | hide(dropped / lingerExpired), stopSampler |
| T17 | wheel, releasing | `escape` | live (or idle if button up) | hide(escape) |
| T18 | wheel | `spaceChanged` | live | hide(spaceChanged) |
| T19 | any | bindings changed | same | none; new masks apply from the next edge |

Edges within `edgeDebounce` of entering `live` are held, not dropped, and fire at the debounce mark with the then-current
set, so a chord pressed together with the drag resolves to the full chord [14 §1.3 step 4].

### 1.5 Numbers

| Item | Value | Source |
|---|---|---|
| Idle wakeups | 0 (event-woken) | [14 §1.3], [10 §8.11] |
| Sampler rate | Display refresh of the screen under the cursor (60–120 Hz), `NSScreen.displayLink` | [14 §1.3 step 2] |
| Detection window after first drag event | 300 ms | [new; P-T1] |
| Missed mouse-up watchdog | 2 Hz, only in `pressed`/`passive` | [14 §1.3 step 3] |
| `edgeDebounce` | 40 ms | [14 §1.3], [02 §7.6] |
| `releaseTimeout` | 150 ms (event-driven; no fixed grace timer) | [spec]; **changes 02 §7.6 `lingerAfterExit` default 350 → 150 ms** |
| Reject pill duration | 1.2 s | [new; P-W1] |
| Payload probe budget | ≤ 8 ms p95 for ≤ 512 items (one 120 Hz frame); beyond 512 items formats come from extensions only | [new; P-T4] |
| Tap → first wheel frame | p95 ≤ 16 ms at 120 Hz, ≤ 33 ms at 60 Hz | [10 §8.11] |
| `honorsModifierHeldAtDragStart` | **false** [critic3]: a key held before the drag is ignored until released and pressed again; `true` = parity behaviour (opens the wheel) | [01-prd FR-4, D-3], [05 D-3] |
| `retapClosesWheel` | true | [spec], [14 §1.3 step 5] |

### 1.6 Payload probe

1. On T4, read `readObjects(forClasses: [NSURL], options: [.urlReadingFileURLsOnly: true])` once on the main actor (C-20 allows
   drag-pasteboard reads; G-0 re-tests with pasteboard privacy on). File promises: count as files, formats unknown.
2. Off-main: `standardizedFileURL`; per item `resourceValues([.isDirectoryKey, .isPackageKey, .contentTypeKey])` for the first
   512; extension-only UTType for the rest. `.pages`/`.rtfd` packages count as files [spec].
3. Build `DragSummary {hasFiles, formats, itemCount, containsFolders, acceptedModes}` with the §2.6 slice builders. Cache by
   `(changeCount, bindings version)`; never re-stat per frame [spec].
4. If the fallback stance is forced by G-0 (reads prompt), summary is types-only (`formats = nil`) and the wheel refines on
   `draggingEntered` [14 §2.2].

### 1.7 Bindings

| Rule | Value | Source |
|---|---|---|
| Storage | One Codable `TriggerBindings {schemaVersion, convert, tools, actions}` | [spec] |
| Defaults | ⇧ convert, ⌘ tools, ⌃ actions | [spec], [D00 O-16] |
| Domain | The 15 non-empty ⌃⌥⇧⌘ sets; empty = wheel disabled, never matches a plain drag | [spec] |
| Validation | Three masks pairwise distinct and non-empty, enforced by the decoder too (unknown or missing `schemaVersion` is a decode error); decode failure → defaults + log | [spec], [review] |
| UI | Shortcut recorder per wheel; conflicts shown inline, not hidden | [spec] |
| Menu summary | `⇧: Convert · ⌘: Tools · ⌃: Actions`, symbols ordered ⌃⌥⇧⌘ | [spec] |

### 1.8 Optional fast paths

| Path | Condition | Effect |
|---|---|---|
| `flagsChanged` listen-only tap | P-T2 shows delivery without permission | Feeds `sample(flagsChanged)` at once; frames only reconcile [15 C-20] |
| Esc | Settings › Keyboard opt-in; Carbon hotkey only while visible (P-T3); fallback Input Monitoring tap | `escape` event; the drag continues [14 §1.3 step 5] |

### 1.9 Trigger design summary

| Aspect | Zivlet |
|---|---|
| Idle cost | 0 wakeups; mouse-down monitor |
| Active rate | Display rate, only after a file drag is detected |
| URL reads | Once per `changeCount`, off-main, capped |
| Tap semantics | Press-edge exact match, plus re-tap closes |
| Rejecting wheel | `reject` effect with reason; state stays consistent |
| Cancel | Re-tap, hub drop, release outside (150 ms), opt-in Esc |
| Release race | Event-driven (`dropHandled`/exit) + 150 ms safety |
| Logging | None |
| Bindings | One validated Codable value |
| Panel | One pre-warmed panel |

---

## 2. Wheel

### 2.1 Panel

| Property | Value | Source |
|---|---|---|
| Class | `WheelPanel: NSPanel`, `[.borderless, .nonactivatingPanel]`, buffered, `defer: false` | [14 §2.1], [spec] |
| Level | `.popUpMenu` (101) | [spec] |
| Collection | `canJoinAllSpaces, transient, stationary, ignoresCycle, fullScreenAuxiliary` | [spec] |
| Look | `isOpaque = false`, clear background, `hasShadow = false` (shadow drawn by SwiftUI) | [spec] |
| Behaviour | `hidesOnDeactivate = false`, `animationBehavior = .none`, `isMovable = false`, `canBecomeKey` only in keyboard mode | [14 §2.1] |
| Size | 372 × 372 pt content (covers the 150 pt hit radius plus highlight scale) | [spec] |
| Lifetime | Created and pre-warmed at launch (ordered in at alpha 0 off-screen for one frame); reused | [14 §2.1], [spec] |
| Content | `WheelDropView: NSView` (drag destination) > `NSHostingView(WheelView)` with no SwiftUI drop modifiers | [14 §2.2] |
| Placement | Centre on the cursor. Shift only if the **disk** (r 125.92 + 8 pt margin) would leave the screen's `visibleFrame`; the panel may overhang | [spec]; P-W3 tests rotate-at-edge |

### 2.2 Geometry (points; Zivlet spec)

| Element | Value | Source |
|---|---|---|
| Hub hole / ring inner | r 42.24 | [spec] |
| Petal inner | r 48.64 | [spec] |
| Petal outer | r 119.52 | [spec] |
| Ring (backdrop disk) outer | r 125.92 (Ø 251.84) | [spec] |
| Gap | 4 pt constant width: edge pulled in by `asin(min(2/r, 0.95))` at radius r | [spec] |
| Outer corner | starts 20.16 pt inside the rim (r 99.36); angular inset `min(0.24·span, 0.15 rad)` | [spec] |
| Inner corner | angular inset `min(0.18·span, 0.18 rad)` | [spec] |
| Label radius | `40 + (119.52 − 40) × 0.56` = 84.53 | [spec] |
| Intro (collapsed) radius | 50.4 | [spec] |
| Highlight scale | 1.05, full-diameter frame so the petal grows outward | [14 §2.3] |
| Format label | 12 pt semibold, tracking 0.35; frame 82 × 24 centred on the label point | [spec] |
| Tool/action label | 7.5 pt semibold, tracking 0.2, frame 82 × 22 below a 12.6 pt SF Symbol | [spec] |
| Hub label | 58 × 28 frame; 10 pt medium (one item) / 7 pt semibold (several), chosen by source item count, not by the text shown; shrink by 0.5 to min 5.5 | [spec] |
| Status pill | 276 × 58, corner 15, 14 pt medium, max 2 lines, kept 12 pt inside the panel | [spec] |
| Max slots | 12 | [14 §2.3] |
| Disk shadow | black 0.32, blur 10, 3 pt drop, masked to outside the disk (never darkens the glass); Solid adds a 1 pt white 0.16 rim | [new] |
| Idle glass scrim | black 0.4 (dark) / white 0.4 (light) under idle petal and hub labels; a faint glass `.tint` measured 2.7:1 over white | [new]; 01-prd FR-26 |

Corner Bézier control points are Zivlet's own design, drawn from the angles above with
`addArc(tangent1End:tangent2End:radius:)`.

### 2.3 Slot ordering

```
n = slots.count;  span = 2π/n;  base = (n == 3) ? π : π/2       // radians, AppKit y-up
centre(k) = base − k·span                                        // slot 0 at 12 o'clock, clockwise; n = 3 starts at 9
```
Source: [spec], [01-prd §5.5]. n = 1 is a full ring; n = 6 (actions) puts AIRDROP at the top.

### 2.4 Hit-testing (`WheelModel.hitTest`, pure)

```
v = p − centre;  r = |v|
if r < 42.24          → .hub                                    // drop here = cancel (snap back)
if r > 150            → .outside                                // generous outer slack beyond the petal rim (119.52)
a    = (base − atan2(v.y, v.x)).truncatingRemainder(2π), +2π if negative
slot = Int((a / span).rounded(.toNearestOrAwayFromZero)) mod n  // sectors centred on petals
if current ≠ nil, slot ≠ current, angularDistance(a, centre(current)) < span/2 + 3°  → keep current
→ .slot(slot)
```

| Decision | Value | Source |
|---|---|---|
| Hub dead zone | r < 42.24 | [spec] |
| Outer slack | to r 150 | [spec] |
| Boundary hysteresis | 3° | [spec] |
| Gaps | Belong to the nearer slot; `HitResult.gap` of 02 §7.7 is not produced | [spec] |
| Drop target | `.slot` with a non-empty action only; hub/outside/empty wheel → `prepareForDragOperation` false | [spec] |
| Highlight update | Only when the slot changes (no per-frame model churn) | [14 §2.3] |

### 2.5 Drop protocol (`WheelDropView`)

| Callback | Behaviour | Source |
|---|---|---|
| `draggingEntered` | Mark pointer inside; strict URL re-read; if it differs from the probe, rebuild slots keeping the hovered slot when it still exists | [spec] |
| `draggingUpdated` | Hit-test; return the **first of `.copy, .generic, .link, .move` present in the source mask**, else `[]` | [15 C-8] |
| `prepareForDragOperation` | true only if a slot is highlighted and the wheel is not empty | [spec] |
| `performDragOperation` | Re-read URLs (or `NSFilePromiseReceiver`s); must equal the probed set; hand `DropIntake` the request; return within 1 ms | [spec], [10 §8.11] |
| Semantics | Always copy: the negotiated operation never moves or deletes a source | [15 C-8] |
| `concludeDragOperation` / `draggingExited` | Emit `dropHandled` / pointer-left to the trigger | [spec] |

### 2.6 Slice lists (`ZivletWheelCore`, data-driven from `Catalog`)

**Convert** (all items must have a format):

| Selection | Slices | Source |
|---|---|---|
| One format | `Catalog.targets(f)` in catalog order, filtered by capability | [spec] |
| Several formats, same family | First format's targets that every other format can also produce, in that order | [spec] |
| Different families | Union of targets, grouped by family, each slice badged "k of n"; only if ≤ 12 slots, else empty | [01-prd FR-20], [new] |
| Folder (not `.pages`/`.rtfd`) | Empty: "Folders work with Actions only" [critic3] | [spec] |

Families: image 0–7, audio, video (**incl. GIF**), document (**incl. PDF**), spreadsheet, archive, subtitle [spec].

**Tools**: per-format table [spec] stored as data (format group × cardinality → tools, flags `hasEditor`,
`supportsMultiple`, `multiInput`):

| Formats | 1 file | ≥ 2 files |
|---|---|---|
| jpg png webp heic tiff | Compress, Metadata, Edit, Annotate, Add BG, Crop, Redact | Compress, Metadata, Crop, Create PDF, Collage |
| svg | Read QR | Create PDF, Collage, Read QR |
| avif, bmp | Read QR | Read QR |
| pdf | Compress, Metadata, Split, Organize, Read QR | Compress, Metadata, Split, Merge PDF, Read QR |
| mp3 m4a wav flac | Compress, Metadata, Normalize, Visualize, Trim, Channels, Bleep | Compress, Metadata, Normalize |
| mp4 mov mkv | Compress, Metadata, Mute, Trim, Crop, Speed, Snapshot, Split, Redact | Compress, Metadata, Mute, Join |
| gif | Metadata, Read QR | same |
| zip tar gz rar | Extract | same |

Mixed tools: same family → intersection in the first format's order, evaluated with the total count; else, if all are raster,
GIF or PDF → `[Read QR]`; else empty [spec]. Gap-fill rows (ogg/opus/aiff/wma, webm/avi/wmv, multi-file Trim/Speed) are
catalog entries flagged `introducedIn: .v1x` [spec].

**Actions**: always AIRDROP, FLOAT, COPY, MOVE, COPY PATH, TERMINAL, folders allowed [spec]. Non-local items → empty with
"Actions work on items stored on this Mac" [critic3: own copy].

**Hub label** [spec]: one file → name (new) + size; n files same type → `"<n> <TYPE> FILES\n<size>"`; mixed → `MIXED`;
folders → `FOLDER` / `"<n> FOLDERS"`; files + folders → `"<n> ITEMS"`; folder sizes computed async (never shown as unavailable)
[spec]. Hovering a slot shows its label.

**Empty states** (mode-correct cases; copy is Zivlet's own [critic3]): convert "These files can't share a format" / "Folders work with Actions only" / "<FMT> needs an engine that isn't installed" / "Zivlet doesn't know this file type"; tools "No tools for <FMT> files" / "No tools for these items"; actions "Actions work on items stored on this Mac"; any "Zivlet can't read one of these files", "Nothing to work on yet". Source of truth: `EmptyReason.message` (06d 7c).

### 2.7 Animation, sound, haptics

| Event | Visual | Sound / haptic | Source |
|---|---|---|---|
| Show | Panel alpha 0 → 1 in 0.07 s ease-out; petals expand from r 50.4 over 0.20 s, curve (0.18, 0.82, 0.24, 1.0); labels 0.10 s from +0.05 s; borders 0.06 s from +0.20 s | — | [spec] |
| Highlight change | Tint + 1.05 scale, `.snappy(0.12)` | `.alignment` haptic at `.now`; tick | [14 §2.3, §2.4] |
| Mode switch | Glass morph by `glassEffectID`, `.spring(duration: 0.28, bounce: 0.15)` | `.levelChange` haptic | [14 §2.3, §2.4] |
| Reject | 3-cycle horizontal shake, 0.24 s; pill 1.2 s | `.generic` haptic | [new; P-W1] |
| Drop accepted | Petal pulse 0.10 s, then hide | `.generic` haptic | [spec], [new] |
| Hide | Scale 1 → 0.96 + fade, 80 ms | — | [spec] |
| Reduce Motion | Springs and intro → 80 ms opacity fades | — | [14 §2.3] |
| Reduce Transparency | `.identity` glass + solid material fill | — | [14 §2.3] |

Glass: one `GlassEffectContainer(spacing: 6)`, `glassEffect(.regular)` per petal, tinted accent when hot; `.interactive()` only
in keyboard/click mode because hover never reaches us during an external drag [14 §2.3]. Accent token: highlight gradient
derived as +24 % white / base / sat ×1.12 bri ×0.74 [spec]; Zivlet's own hue.

Tick: original 20–40 ms sample, `AudioServicesPlaySystemSound`; at most one per 35 ms; requests older than 150 ms dropped;
silent when the system UI-sound setting is off (P-W4) [14 §2.4], [spec]. Separate Sound and Haptics toggles,
both default on [spec].

### 2.8 Keyboard mode

| Item | Behaviour | Source |
|---|---|---|
| Entry | Global hotkey (KeyboardShortcuts, default unset, suggested ⌃⌥⌘S) or Services; never bare Enter | [14 §4.6], [01-prd NG9] |
| Selection source | Services pasteboard; Finder selection via Apple Events only if the opt-in is on (off by default) | [14 §4.6], [D00 O-17] |
| Panel | `keyboardMode = true; makeKey()` without activating the app | [14 §4.6] |
| Anchor | Mouse location | [14 §4.6] |
| Keys | ←/→/Tab rotate; 1–9 pick slot; type-to-filter; bound modifier taps switch wheel; Return applies; Esc closes | [14 §4.6] |
| Accessibility | Petals become `Button`s with labels; VoiceOver operable | [14 §4.6], [spec] |

---

## 3. Catalog and routing

### 3.1 Format registry (`ZivletCore.Format`)

| Field | Example | Notes |
|---|---|---|
| `id` | `.heic` | 46 formats: 45 inputs + `html` output-only [01-prd §6.1] |
| `extensions` | `["heic","heif"]` | First is canonical (output extension) |
| `contentTypes` | `["public.heic"]` | Mid-drag lookup key |
| `family` | `.image` | §2.6 families |
| `role` | input / output / both | Input-only: rar ppt xls rtf rtfd textClipping svg [01-prd §6.1] |
| `displayLabel` | `"HEIC"` | Upper-case extension; gz → `GZIP` [01-prd §5.5] |
| `isPackage` | `pages`, `rtfd` | Directory accepted as a file [spec] |

### 3.2 Content sniffing

Two stages. Mid-drag: extension + `contentType` only (cheap). At admission (worker): read the first 4 KB and match signatures;
the sniffed type wins.

| Signature (offset: bytes) | Format |
|---|---|
| 0: `FF D8 FF` | jpg |
| 0: `89 50 4E 47 0D 0A 1A 0A` | png |
| 0: `RIFF`, 8: `WEBP` / `WAVE` / `AVI ` | webp / wav / avi |
| 4: `ftyp` + brand `heic heix hevc mif1` / `avif avis` / `M4A ` / `qt  ` / `isom mp41 mp42 avc1` | heic / avif / m4a / mov / mp4 |
| 0: `II*\0` or `MM\0*` | tiff |
| 0: `BM` | bmp |
| 0: `GIF87a` / `GIF89a` | gif |
| 0: `%PDF-` | pdf |
| 0: `ID3`, or frame sync `FF Fx` | mp3 |
| 0: `fLaC` | flac |
| 0: `OggS` + `OpusHead` / `\x01vorbis` in first page | opus / ogg |
| 0: `FORM`, 8: `AIFF`/`AIFC` | aiff |
| 0: ASF GUID `30 26 B2 75 8E 66 CF 11`; video stream present / absent | wmv / wma |
| 0: `1A 45 DF A3` + DocType `webm` / `matroska` | webm / mkv |
| 0: `PK\3\4` + entry `[Content_Types].xml`+`word/`·`ppt/`·`xl/` / `mimetype`=`application/epub+zip` / `Index/Document.iwa` / ODS mimetype | docx · pptx · xlsx / epub / pages / ods / else zip |
| 0: `D0 CF 11 E0 A1 B1 1A E1` (CFB) + stream names | ppt / xls |
| 0: `Rar!\x1A\x07` | rar |
| 0: `1F 8B` | gz |
| 257: `ustar` | tar |
| 0: `{\rtf` | rtf |
| text: `<svg` (after XML prolog), `WEBVTT`, SRT cue pattern, UTF-8/16 text | svg, vtt, srt, txt/csv/tsv/md (by extension) |

Mismatch policy: if sniffed ≠ extension and both are known → route by the sniffed format and note it on the card; unknown
signature for a binary format → `unsupportedInput("contents don't match the extension")`. For ffmpeg inputs the sniffed
demuxer becomes the forced `-f` [10 §8.9 challenge]. Signatures are standard format facts.

### 3.3 Route matrix data model

```swift
public struct Route: Sendable, Hashable, Codable {          // 02 §7.1, plus three fields
    public let source: FormatID, target: FormatID
    public let engines: [EngineID]                             // ordered preference
    public let fallbackOnFailure: Bool                         // only resvg → NSImage → WebKit, LO → Tier 1
    public let options: [OptionKind]                           // which per-output settings apply [spec]
    public let introducedIn: Milestone
}
```

- Source of truth: one Swift literal table, 275 pairs in catalog order (= petal order) [01-prd §6.1]; extras
  behind the same table [10 §4.14].
- Tests: count = 275; per-input order equals the catalog order; every route has ≥ 1 engine; every engine ID resolves.
- `Catalog` drives the wheel, App Intents, Services, `zivlet formats --json`, the Settings compatibility list [10 §7.3].

### 3.4 Engine selection

| Step | Rule | Source |
|---|---|---|
| 1 | Drop routes whose every engine fails the capability gate (route hidden in the wheel; reason in Settings) | [10 §8.8] |
| 2 | Plan with the first engine whose gate passes and whose pure `plan()` accepts the probe | [02 §7.3] |
| 3 | Document routes: order chosen by Document fidelity (Automatic / Fast / Best) | [10 §4.1] |
| 4 | Execute-time fallback only if `fallbackOnFailure`; the card names the engine used | [10 §4.3] |
| 5 | Per-file gating at probe: e.g. video → MP3 hidden when there is no audio track (hover probe, 150 ms budget, cached by path+size+mtime) | [11 §8.2] |

### 3.5 Capability gating

| Gate | Probe | Example effect |
|---|---|---|
| ImageIO writable UTI | `CGImageDestinationCopyTypeIdentifiers()` | AVIF output hidden or ffmpeg fallback (G-0) [10 §4.2 fn 1] |
| ffmpeg encoders/muxers/filters | `-encoders -muxers -filters`, keyed by binary hash | WebM hidden if libvpx missing (never shown broken) |
| VideoToolbox | session creation at probe | VT → libx264 fallback [11 §9] |
| AV1 HW decode | `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` | AV1 copy into MP4/MOV [15 C-9] |
| Vision requests | availability per OS | OCR routes |
| Optional engines | LibreOffice / iWork present | PPT routes [10 §3] |
| Helper integrity | `SecStaticCodeCheckValidity` | `engineDamaged` [10 §8.9] |

Cache: `~/Library/Caches/<bundle>/Capabilities/<binaryHash>-<osBuild>.json`, rebuilt on update or OS change [10 §8.6, §8.8].

---

## 4. Job runtime (`ZivletRuntime`)

### 4.1 Lifecycle

`Request → Probe → Plan → Admit → Execute (stages) → Verify → Publish → Report`; one immutable value per step [10 §8.1].
`JobState`: queued, probing, planned, running(progress), verifying, publishing, succeeded, failed, cancelled [02 §7.2].

### 4.2 Scheduler lanes

| Lane | Width | Work | Source |
|---|---|---|---|
| `cpu` | P-cores (`hw.perflevel0.physicalcpu`) | ImageIO, Core Image, libwebp, resvg, PDFKit, qpdf, libarchive, writers | [10 §8.1] |
| `remux` | 4 | ffmpeg copy, mute, fast trim, copy-only metadata | [10 §8.1] |
| `audio` | P-cores | ffmpeg audio encodes | [10 §8.1] |
| `hwVideo` | 2 (3–4 on Max/Ultra) | VideoToolbox | [10 §8.1] |
| `swVideo` | 1 | libvpx-vp9, SVT-AV1, x264 | [10 R-4] |
| `render` | 1 until D-PRINT2 | WKWebView print (MainActor) | [10 §8.1 challenge] |
| `js` / `vision` / `metadata` / `office` / `iwork` | 2 / 1 / 1 / 1 / 1 | helpers | [10 §8.1] |

| Rule | Value | Source |
|---|---|---|
| Memory pressure | `.warning` halves widths; `.critical` pauses admission | [10 §8.1] |
| Low Power Mode | halves `cpu` | [10 §8.1] |
| Limiter | Own cancellation-aware async semaphore (~40 lines, tested) | [14 §5.2] |
| Fairness | Round-robin across batches per lane; newest visible batch first on ties | [spec] |
| Multi-stage plans | Acquire each stage's lane in turn; release between stages | [10 §7.3] |
| Worker crash | Retry in-flight jobs once, one at a time; second crash → "This file made the engine crash" | [10 §8.1] |
| Disk preflight | free ≥ 1.5 × estimated output + 512 MB, else `diskFull` before start | [10 §8.6] |
| QoS | `USER_INITIATED` for wheel drops, `UTILITY` for batches > 20 | [14 §5.2] |
| Quit | `.terminateLater` → cancel all → wait ≤ 2 s → reply | [10 §8.1] |

### 4.3 Staging and atomic publish

| Step | Rule | Source |
|---|---|---|
| Staging dir | `url(for: .itemReplacementDirectory, appropriateFor: destDir)` (same volume) | [10 §8.5] |
| Fallback | Hidden `.zivlet-<uuid>/` in the destination (SMB/FAT) | [10 §8.5] |
| Scratch | `~/Library/Caches/<bundle>/Jobs/<uuid>/` + `job.json` | [10 §8.6] |
| Verify | Engine `VerificationSpec` (e.g. ffprobe streams, duration ±max(0.25 s, 1 %), size > 0) before publish | [11 §8.4] |
| Attributes | Copy `com.apple.quarantine` from any quarantined input onto every staged output; optional Finder tags/comment | [10 §8.5 challenge] |
| Name claim | `NameReserver` actor proposes the next free candidate (case-folded key on case-insensitive volumes) | [10 §8.5] |
| Publish | `renamex_np(staged, dest, RENAME_EXCL)`; `EEXIST` → next candidate; folders publish the same way | [10 §8.5] |
| Attempts cap | 9,999 candidates, then `publishFailed` | [new] |
| Unwritable destination | Re-stage under `~/Downloads` (configurable) and say so on the card | [10 §8.5] |
| Cloud/SMB | After rename on a non-APFS-local volume, confirm via a `DispatchSource` directory watch, 8 s timeout | [spec] |
| Never | Overwrite, touch the source, or leave a partial file at the final name | [spec] |

### 4.4 Output naming (`OutputNamer`, pure)

| Case | Pattern | Source |
|---|---|---|
| Conversion | `<base>.<ext>` | [01-prd §5.9] |
| Base | strip compound `.tar.gz .tgz .tar.xz .tar.bz2 .tar.zst` as one unit, else the last extension | [spec] |
| gz target | writes `.tar.gz` | [01-prd §5.9] |
| Tool | `<base> <Suffix>.<ext>` | [01-prd §5.9] |
| Multi-input tool | `<first base> <Suffix>.<ext>` in the first file's folder | [10 §8.5] |
| Collision | `<name> 2.<ext>`, `<name> 3.<ext>`: one ASCII space, decimal, no padding | [spec] |
| Folder output | `<base> <Suffix>` → `<base> <Suffix> 2` | [spec] |
| Folder items | `Page 001.<ext>` with width `max(3, digits(count))`; `Clip 001`, `Slide 001`, `Frame 001 - 12.345s.png` | [spec], [10 §8.5] |
| Extension case | Format's canonical lower-case extension | [spec] |
| Length | Truncate `<base>` (grapheme-safe) so the UTF-8 name ≤ 255 bytes including suffix and counter | [new] |
| Safety | Every name is one path component: `/`, `:` and Unicode Cc characters (NUL included) in the stem or folder-item prefix become `-`; an empty, whitespace-only, `.` or `..` stem becomes `Untitled`; extensions must match `[a-z0-9]+(\.[a-z0-9]+)*`, ≤ 16 bytes, else `NamingError.invalidExtension`. Applies to decoded names too. The runtime join (P1) still creates the staged file exclusively | [review] |

Tool suffixes (parity default = native names [15 C-19]):

| Tool | Suffix | Tool | Suffix |
|---|---|---|---|
| Compress | `Compressed` (wav/aiff → `.flac`) | Trim Video/Audio | `Trimmed` |
| Metadata strip (images) / edit (images) | `Metadata Removed` / `Metadata Edited` | Normalize | `Normalized` |
| Metadata strip (PDF, A/V) | `No Metadata` | Mute | `Muted` |
| Edit Photo | `Edited` | Bleep | `Bleeped` |
| Annotate | `Annotated` (`.png`) | Speed | `Speed 2.0x` (Swift `Double.description`) |
| Add BG | `With Background` | Snapshot(s) | `Snapshot` (`.png`) / folder `Snapshots` |
| Crop Image/Video | `Cropped` | Split Video / Split PDF | folder `Clips` / `Pages` |
| Redact | `Redacted` | Organize PDF | `Organized` |
| Create PDF / Merge PDF | `<first> Images.pdf` / `<first> Merged.pdf` | Extract | folder `Extracted` |
| Join / Collage | `Joined` (`.mp4`) / `Collage` | Visualizer / Channels | `Visualizer` (`.mp4`) / `Mono`·`Stereo` |
| PDF → images | folder `<base> <EXT> Pages` | Multi-frame image → stills | folder `<base> Images` |

Source: [01-prd §6.2]. Any deviation is an explicit O-16 row [15 C-19].

### 4.5 Progress

| Item | Rule | Source |
|---|---|---|
| Model | `JobProgress {stage, stageCount, fraction?, bytesWritten?, eta?}` as `AsyncStream`, throttled to 10 Hz | [10 §8.2], [02 §7.2] |
| Monotonic | Item and overall fractions never decrease | [spec] |
| ffmpeg | `out_time_us / expected`; expected from the plan (trim range, ÷ speed, sum of clips); ETA from `speed=` | [10 §8.2] |
| Stage weights | x264 2-pass 0.35/0.65; loudnorm 0.40/0.60; plan-supplied otherwise | [10 §8.2] |
| Batch weight | duration × pixels (video), page count (docs), bytes otherwise | [10 §8.2] |
| Unknown duration | Indeterminate bar + bytes written | [10 §8.2] |
| HUD | Cursor-anchored, 12 pt screen clamp, cascade 24 pt; "n of m saved"; done card with thumbnail, before → after size, Undo, Reveal, Open, Copy, drag-out; success card stays 4 s, held while hovered [critic3: 01-prd §5.8; 1.5 s leaves too little time to reach Undo] | [spec], [01-prd §5.8] |
| Reveal | One Finder reveal per batch, setting "Reveal results in Finder", default **on** (parity; 01-prd §5.8) [critic3: was off; **[OWNER]** may choose off] | [spec] |

### 4.6 Cancellation

| Layer | Mechanism | Target | Source |
|---|---|---|---|
| User | HUD/menu Cancel → `Task.cancel()`; state `.cancelled` at once; staging deleted; never published | ≤ 100 ms visible | [10 §8.3] |
| ffmpeg, perl, zivlet-js | swift-subprocess teardown: SIGINT → SIGKILL at +1 s to the process group | gone ≤ 1 s | [10 §8.3] |
| LibreOffice | SIGTERM → SIGKILL at +5 s; 120 s per-file watchdog | ≤ 5 s | [10 §8.3] |
| WebKit | `stopLoading()`; view discarded | ≤ 200 ms | [10 §8.3] |
| In-worker C libraries | Cooperative checks between entries/pages/frames; stuck call → watchdog kills and relaunches worker | ≤ watchdog | [10 §8.3] |
| Watchdogs | JS 60 s, render 90 s, Vision page 30 s, ExifTool 10 s; ffmpeg stall detector: `out_time` flat 60 s | — | [10 §8.3] |
| Close ≠ cancel | Closing the HUD keeps jobs running; Cancel is a separate control | — | [spec] |

### 4.7 Undo

| Item | Rule | Source |
|---|---|---|
| Entry | Per batch: `{batchID, date, outputs: [path, fileResourceIdentifier, size, mtime]}`; Move entries also store each source path | [10 §8.5], [10 §6 #4] |
| Undo (convert/tool) | Move each output to the Trash **only if** identifier, size and mtime still match; else skip and list it | [01-prd FR-39], [new] |
| Undo (Move) | Move items back to their original folders, collision rule applies | [10 §6 #4] |
| Retention | Last 20 batches, `~/Library/Application Support/Zivlet/undo.json`, expire after 24 h | [new] |
| Surfaces | Result card button; status menu "Recent results" | [14 §3.1] |

### 4.8 Orphan reaper (launch)

1. For each `Caches/<bundle>/Jobs/<uuid>/job.json {pid, pgid, start, helperPath, stagingPaths}`: if `proc_pidpath(pid) ==
   helperPath`, `killpg(pgid, SIGKILL)` [10 §8.3].
2. Delete the recorded `stagingPaths` (`.zivlet-<uuid>` dirs, replacement dirs), so no staging files are left
   beside originals after a crash.
3. Delete the job directory; sweep any job directory older than 24 h; trim `Proxies/` to 2 GB LRU [10 §8.6].

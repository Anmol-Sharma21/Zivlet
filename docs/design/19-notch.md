# 19 — Notch island: spike P2-197, NotchIsland core and Notch HUD (M5a), notch Drop Box (M5b sketch)

Date: 2026-10-22. Status: design for the owner, with spike evidence. Inputs: [00-decisions](00-decisions.md)
(OWN-PLAN-3, OWN-HUD-1 and its defaults, OWN-HUD-2 resolved 2026-10-23, OWN-UI-1, OWN-APP-2), [17e-app §2 and §2a](17e-app.md),
[17-feature-roadmap](17-feature-roadmap.md) (W-8, W-9, R7), [01b-prd-additions](../plan/01b-prd-additions.md)
(FR-132, FR-133, FR-150), [05-task-list](../plan/05-task-list.md) (P2-197, P2-115, P2-116, P2-141, P2-55, P2-142,
P2-143), [02-architecture](../plan/02-architecture.md) (§4 modules, R1–R9, ADR-02), [11-m4-record](../plan/11-m4-record.md)
(D-M4-16, D-M4-22, G-M4-10) and the M4 code in `ZivletUI/HUD`, `ZivletSettings` and `ZivletWheelCore/PanelPlacer.swift`.
The implementation plan is [12-implementation-plan-m5a-notch](../plan/12-implementation-plan-m5a-notch.md).

Revised the same day after a review of the plan: D-N3, D-N4, D-N6 … D-N9 changed and D-N11 … D-N13 were added;
§3.2, §3.4, §4, §5, §6, §9, §10 and §11 changed with them. The plan's §4 lists every review finding, what was taken
and what was not, with the reason.

This file supersedes the module placement proposed in 17e §2a.3 ("a new AppKit module `ZivletNotch` … settled in
P2-197"): the spike settles it as two modules (§3.1, D-N1). D-N3 also replaces 17e §2a's "ears" with a tab below the
housing, so 17e's "label in the ear" and "3 jobs" in the ear now mean the tab. Everything else in 17e §2a still holds
unless a row below says otherwise.

Clean room: prior-art apps are described only by their general, user-visible behaviour, in our own words, from their
public descriptions (§1.3). No code, strings, assets or sounds come from the reference app, Open-Tangerine or any
notch or shelf app; several of them are GPL-licensed or unlicensed, and we read none of their source. Every UI string
quoted here is Zivlet's own wording.

---

## 1. Spike P2-197: what was measured

### 1.1 Set-up

A throwaway AppKit program, outside the repository and not published, built with `swiftc -O` (Swift 6.4, Xcode 27).
It reads every `NSScreen`'s geometry, shows a borderless non-activating `NSPanel` shaped like an island at the notch,
and takes commands (expand, collapse, hide, measure, key, list windows) through a FIFO, so nothing polls. A second mode
opens a plain window of its own and puts it in full screen, so the island could be checked over another process's
full-screen Space without scripting any other app. Screenshots were taken with `screencapture -x` and cropped to the
island.

Mac: 14-inch MacBook Pro, M2 Pro, macOS 27.0 (build 26A428, both as `sw_vers` reports them; checked again after the
review), one display (built-in, no external display connected). The
display was in the scaled mode 1800 × 1169 pt (3600 × 2338 px backing). Load average 2.6–3.3 when the run started
(photo analysis in the background), and the owner was using the Mac: the frontmost app changed between runs.
Treat the timings as upper bounds.

### 1.2 Results

| # | Question | Result |
|---|---|---|
| S1 | Notch geometry from public API | `frame` 1800 × 1169; `visibleFrame` y 94, height 1036 (top inset **39** pt, Dock 94 pt); `safeAreaInsets.top` **38**; `auxiliaryTopLeftArea` (0, 1131, 790 × 38); `auxiliaryTopRightArea` (1010, 1131, 790 × 38). So the housing is the **220 × 38 pt** gap between the two areas, flush with the top edge. The menu bar's inset (39) is one point taller than the safe-area inset (38): the layout must use the safe area for the island and `visibleFrame` only for the pill |
| S2 | Can content sit inside the notch rectangle? | **No.** The screenshot holds the pixels behind the camera housing (the icon and ring we drew there are in the image), but on the panel they are physically covered. Collapsed content must sit outside the housing (the spike tried "ears" beside it; D-N3 now puts it in a tab below it); a collapsed shape exactly the notch's size shows nothing to the person (shots 01, 02) |
| S3 | Above the menu bar | Window list (`CGWindowListCopyWindowInfo`, no permission needed for bounds and layers): menu bar = layer **24**, our panel at `.statusBar` = layer **25**, above it. The wheel (`WheelPanel`) and open menus are at `.popUpMenu` (101), so both stay above the island. A borderless panel may be placed over the menu-bar strip; its frame read back unchanged |
| S4 | All Spaces and full screen | With `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` the island stayed on screen when the helper window entered a full-screen Space (`isOnActiveSpace` true, occlusion state visible). In that Space the app's window starts at y 39 and the strip beside the camera stays black; the collapsed island sits in the strip, and the expanded card draws over the app (shots 07, 08) |
| S5 | Focus | Showing, expanding and collapsing never changed the frontmost app, `NSApp.isActive` stayed false and the panel never became key. `makeKey()` (what a click into the card does, D-M4-16) made the panel key and set `NSApp.isActive` to true while the frontmost app, and so the menu bar, stayed the person's app. So keyboard focus moves only on a click, as with today's HUD card |
| S6 | Expand latency, spring (response 0.38, damping 0.78) | First expand after each launch: state change committed in 28–46 ms, first display-link frame after **35–53 ms** (five launches). Warm (five more cycles): committed in 15.1–19.5 ms, first frame after **17.2–22.2 ms**. Settled after 402–436 ms (the slowest were first expands after a launch). Collapse (response 0.32, damping 0.9) settled after 335–339 ms |
| S7 | Reduce Motion (cross-fade 0.18 s, no size spring) | Warm: first frame after 21.0–25.3 ms, settled after 207–213 ms; collapse 192–197 ms. First expand after launch: 72.6 ms (outlier, cold SwiftUI layout) |
| S8 | Idle CPU (rusage over 10.5 s; `top` alongside) | Collapsed, nothing changing: **0.014 %**. Expanded, nothing changing: **0.007 %**. Hidden (ordered out): 0.034 %. `top` showed 0.0 % and the idle wake-up counter did not grow in these states. Collapsed with a SwiftUI progress ring redrawn at 10 Hz: **1.65 %**. Memory: 16 MB footprint, 43 MB resident |
| S9 | Hover without permissions | A tracking area (`.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`) on the panel needs no permission. **Not verified with a real pointer**: nobody pointed at the island during the runs, so it logged no enter events (owner QA). The M4 HUD's hover in the same kind of panel works on this Mac (the M4 review fixed its stale hover flag), which is supporting evidence only |
| S10 | Global `mouseMoved` monitor | Works without a prompt: 398 events in 21 s while the owner moved the pointer. It costs CPU even with an empty handler: **0.86 %** over those 21 s. Not used (D-N6) |
| S11 | TCC | **No prompt** and no non-preflight request. tccd logged, for the prototype, one `kTCCServiceListenEvent` check with `preflight=yes` (answer: not allowed) at each launch of the AppKit process, before any monitor was installed; installing the global monitor added none. WindowServer also made `kTCCServiceScreenCapture` preflight checks at the moments `screencapture` ran (attributed to the terminal). The M5a exit check therefore counts requests with `preflight=no` for Zivlet, not every tccd line (§9) |
| S12 | Display without a notch | No external display was connected. The pill was exercised by forcing "no notch" on the built-in display: 200 × 28 pt, 6 pt under the menu bar, expanding to the card the same way (shots 05, 06). Real external display, lid closed, Stage Manager and Spaces switching are owner rows (§10) |

Screenshots (local, not published): 01 collapsed at exactly the notch's size; 02 collapsed with 40 pt ears; 03
expanded card; 04 Reduce Motion mid-fade (already near full opacity when captured); 05 pill collapsed; 06 pill
expanded; 07 collapsed over a full-screen window; 08 expanded over a full-screen window.

What the spike did not settle: how the hover feels with a real pointer (intent delay, accidental opens), whether the
ears collide with menu-bar items on a crowded menu bar, a 16-inch notch and other scaled modes (only one mode was
recorded, §3.3), and 120 Hz smoothness.

### 1.3 Prior art, in our own words

From public descriptions only (project pages and reviews; no source read):

- **Notch shelves.** One open-source shelf turns the strip around the camera into a drop zone: files dragged onto
  it are kept for a while (one day by default, adjustable), one click opens a file, and there is an AirDrop target.
  A commercial app with a similar tray keeps dropped files until they are dragged out or removed by an "x" on hover,
  and offers the tray and AirDrop as two targets when a drag comes near the notch.
- **Notch "islands".** Several apps open a panel when the pointer reaches the notch (some also on a click or a
  trackpad swipe) and show media controls, a calendar or a replacement for the system volume indicator. On a display
  without a notch, one of them draws a smaller shape at the top centre.
- **A library for developers.** It wraps an app's own views in a notch-shaped window and switches to a floating
  style automatically on Macs without a notch.

What we take: glanceable status where the eye already goes, details only on hover, nothing that takes focus, a
top-centre shape on displays without a notch, and a drop target near the notch during drags (M5b). What we leave out:
widgets, media, calendar and webcam features, swipe gestures, and any system-indicator replacement.

---

## 2. Decisions from the spike

| ID | Decision | Why (evidence) |
|---|---|---|
| D-N1 | Two new modules: pure **`ZivletNotchCore`** (geometry, layout, island state machine, arbiter) and AppKit **`ZivletNotch`** (panel, screen reader, host). The Notch HUD's content and board live in `ZivletUI`; the tray client will live in `ZivletActions` (M5b) | Same split as `ZivletTrigger`/`ZivletTriggerHost` and `ZivletWheelCore`/`ZivletWheel` (ADR-02); the core obeys R1 and is tested without a window server; neither `ZivletUI` nor `ZivletActions` has to import the other (17e §2a.3) |
| D-N2 | Panel: borderless, `.nonactivatingPanel`, level `.statusBar`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `hidesOnDeactivate = false`, not movable, no window shadow, `canBecomeKey` true with `becomesKeyOnlyIfNeeded`, `canBecomeMain` false | S3, S4, S5. `.statusBar` is above the menu bar but below the wheel and open menus, so W-8 holds by stacking alone. `.stationary` instead of the HUD's `.transient`, so Mission Control does not sweep it away |
| D-N3 | Collapsed shape on a notch display = the housing, a **6 pt shoulder** on each side, and a **24 pt tab** below the housing; the collapsed content (icon, count, ring) sits in the tab. Nothing is drawn inside the housing rectangle. The collapsed island, which can stay for minutes, covers at most 6 pt of the menu bar on each side of the housing (§5.3). *Revised after the review:* the first design put 38 pt ears beside the housing | S2. S1: the auxiliary areas are the menu bar's own regions and end exactly at the housing, so macOS lays out app menus up to x 790 and status items from x 1010. On a crowded menu bar, 38 pt ears (752–790, 1010–1048) cover the last menu title and the leftmost visible status item and take their clicks for the whole job. An icon-only ear is no fallback because the ear was already icon-only. Owner point OP-6 |
| D-N4 | The window's frame is the current shape's bounding box. Expanding first sets the larger frame (transparent), then springs the shape inside it; collapsing springs the shape, then shrinks the frame when the animation completes. Every applied effect bumps a **generation token**; a completion that finds a newer token does nothing (no stale `orderOut`, no stale shrink), as `WheelController.hide` already does with `finishHide(mine)`. During the ≈ 400 ms of a resize, the transparent part of the larger frame may take clicks; accepted, because it lasts only for the animation | Click-through outside the shape without per-pixel hit tricks: in the steady state the frame is the shape, so menu-bar items beside it keep working (S6 shows the frame swap costs nothing visible). Without the token, "toast expires, new job starts during the fade" would order out a live island, and "leave, re-enter during the collapse" would clip an expanded card |
| D-N5 | Motion: spring response 0.38 / damping 0.78 to expand, 0.32 / 0.9 to collapse; Reduce Motion → a 0.18 s cross-fade and no size change in view; the island never scales or bounces under Reduce Motion | S6, S7 |
| D-N6 | Hover by **one tracking area sized to the current shape**, not the window, rebuilt in `updateTrackingAreas` after every frame or shape change. After every frame change and order-front, the host compares `NSEvent.mouseLocation` with the shape and sends the matching `pointerEntered` or `pointerExited`, because AppKit sends neither when a frame moves under a resting pointer. Enter events are ignored while a collapse runs. No global mouse monitor, no event tap | S9, S10, S11. A `.inVisibleRect` area on the panel would cover the whole transparent box during a resize, so a pointer near the shape could re-expand a collapsing island again and again, and a shrink under a still pointer would leave a stale "inside" (the bug the M4 review fixed in the HUD). The spike never tested hover with a real pointer, so Q1 covers each of these cases |
| D-N7 | Hidden means ordered out, with no timers and no display link; progress is redrawn only when the shown percent changes, at most 4 times a second, and the ring is a shape whose trim changes (no per-frame animation). A job of unknown length shows a **stepped glyph** (8 positions) advanced at most 4 times a second, not a continuous spinner | S8: idle ≈ 0, but a naive 10 Hz ring costs 1.65 %. A spinner is a per-frame animation and the costliest idle state; X6 measures the stepped glyph |
| D-N8 | One host per display, **created and pre-warmed for every current display** at launch and on each display change (ordered out, so cheap); a job's island is on the display where its drop happened. `IslandHosts` alone owns display changes (§5.2) | 17e §2a.3 rule, OWN-HUD-1 default. Creating hosts on demand would build the panel and hosting view on the first drop's path on each display |
| D-N9 | Pre-warm: each host builds its panel and content view when it is created (D-N8), off the drop path, as `ResultHUD` keeps a spare panel | S6: the first expand after a launch takes 35–53 ms to its first frame, the next ones 17–22 ms; the budget is 50 ms |
| D-N10 | The island is solid black in both appearances, with white text (secondary text white at 0.8). No glass, so Reduce Transparency changes nothing; Increase Contrast adds a 1 pt white outline at 0.5 | Black continues the hardware housing; white on black is 21:1 and white at 0.8 on black about 13:1, above 4.5:1 over any backdrop (D-M4-22's worst case does not arise) Superseded below the housing on 2026-10-23 by OWN-UI-1 (Liquid Glass in the notch design pass; the part that meets the notch stays black) |
| D-N11 | **One clock.** The host reads `now` from `ContinuousClock` and sleeps until deadlines on the same clock; a sleep that wakes before its deadline reschedules. A linger that spans system sleep has therefore passed on wake, and the toast leaves at once; failures have no deadline and stay | `ResultHUD` (M4) reads `now` from `systemUptime`, which stops during system sleep, but sleeps with `Task.sleep(for:)`, whose clock keeps counting. After a wake the timer is not yet expired and nothing reschedules, so the card never leaves. The plan fixes `ResultHUD` too (task N8) |
| D-N12 | **A path that needs no pointer.** A status-menu command "Show Progress and Results" (*new*) sends `expandRequested` and makes the island key, so Tab and Escape work at once. The status menu already lists Cancel for each running batch and Undo for recent results (M4). The collapsed island's accessibility group offers a custom action with the same name that sends `expandRequested` (reachable from VoiceOver's actions menu and Switch Control) | Cancel, Undo, Reveal, Open, Copy and Retry would otherwise sit behind hover, and keyboard focus arrives only after a click (G-M4-10). Keyboard-only, Voice Control and Switch Control users need a way in (WCAG 2.1.1, 2.5.1) |
| D-N13 | **Holds.** The island and the client's lingers are held while the pointer is inside, while accessibility focus is inside, and while a drag that started in the island is in flight. With VoiceOver or Switch Control running (`NSWorkspace.isVoiceOverEnabled`, `isSwitchControlEnabled`), toast lingers are three times as long | A drag leaves the panel, so `pointerExited` would collapse the island under the drag. A 1.5 s or 4 s toast is too short to reach with a screen reader or a switch (WCAG 2.2.1). Voice Control cannot be detected with public API; for it the status menu's Undo has no time limit |

---

## 3. Architecture

### 3.1 Modules

```text
ZivletCore ──────────────┐
  └─ ZivletNotchCore     │  pure: Rect2D (moved from WheelCore), DisplayGeometry, NotchGeometry, IslandLayout,
       └─ ZivletNotch    │        IslandMachine, IslandArbiter, IslandMotion
            ├─ ZivletUI  │  AppKit: IslandPanel, ScreenGeometryReader, IslandHost, IslandShape
            ├─ ZivletActions (M5b: tray client)
            └─ ZivletWheel   (last phase: picker at the notch)
ZivletSettings: HUDPlacement, HUDGroup (no AppKit)
```

| Module | Layer | Imports | Contents | Isolation |
|---|---|---|---|---|
| `ZivletNotchCore` | domain | Foundation, `ZivletCore` | `DisplayGeometry`, `NotchGeometry`, `IslandLayout`, `IslandMachine` (+ events, state, effects), `IslandArbiter`, `IslandMotion` | nonisolated, all values `Sendable` (R1) |
| `ZivletNotch` | shell | AppKit, SwiftUI, `ZivletNotchCore` | `IslandPanel`, `ScreenGeometryReader` (implements `DisplayGeometryProvider`), `IslandHost`, `IslandHosts` (one host per display, sole owner of display changes; built once by `AppDelegate` and injected into every client), `IslandShape`, `IslandChrome` (tab and card frame) | `MainActor` (shell settings) |
| `ZivletUI` (grows) | shell | + `ZivletNotch` | `NotchHUDBoard` (pure struct), `NotchHUD` (presenter), `NotchHUDViews`, `HUDPresenter` and `ActionPresenter` protocols; extracted surface-free HUD content | `MainActor` |
| `ZivletSettings` (grows) | domain | unchanged | `HUDPlacement`, `HUDGroup`, its store key and validation | nonisolated |

`Rect2D` moves from `ZivletWheelCore/PanelPlacer.swift` to `ZivletCore/Shared/` next to `Point2D` (four files use
it), so the notch core does not depend on the wheel core. Its `CGRect` bridge (`Rect2D(_:)`, `.cgRect`, today public in
`ZivletWheel/WheelController.swift`) moves with it; `CGRect` comes with Foundation on Darwin, so `ZivletCore` gains no
import and R1 holds. Both new modules join the coverage gate (80 %): 14 gated modules instead of 12.

### 3.2 Geometry provider

```swift
/// One display as the island sees it; all values in global points, AppKit orientation.
public struct DisplayGeometry: Sendable, Equatable, Codable {
    public let id: UInt32              // CGDirectDisplayID
    public let frame: Rect2D
    public let visibleFrame: Rect2D
    public let safeAreaTop: Double
    public let auxiliaryTopLeft: Rect2D?
    public let auxiliaryTopRight: Rect2D?
    public let isBuiltIn: Bool         // CGDisplayIsBuiltin
}

@MainActor public protocol DisplayGeometryProvider: AnyObject {
    var displays: [DisplayGeometry] { get }          // first = the menu-bar display
    /// A new stream per call; every subscriber gets each change (the same fan-out as `SettingsStore.changes`).
    var changes: AsyncStream<[DisplayGeometry]> { get }
    /// True once this Mac has shown a built-in display with a housing (see below); never false again.
    var hasBuiltInNotch: Bool { get }
}
```

`NotchGeometry.housing(of:)` returns the housing rectangle or nil: nil unless `safeAreaTop > 0`, both auxiliary areas
exist and the right one starts after the left one ends. No sizes are hard-coded; a display that reports a safe area
but no auxiliary areas gets the pill. `ScreenGeometryReader` maps `NSScreen` to these values and re-reads them on
`NSApplication.didChangeScreenParametersNotification`; tests use a fake provider with recorded values. `changes` is
per subscriber because `IslandHosts`, `SettingsModel` and the app's routing all listen; one `AsyncStream` would hand
each change to only one of them.

**`hasBuiltInNotch` is a property of the Mac, not of the current displays.** Rule chosen: a latch. It turns true the
first time the reader sees a built-in display (`isBuiltIn`) that has a housing, and the fact is stored in the app's
defaults under `notch.builtInSeen.v1` (not a Settings group: it never shows in the picker; Copy Diagnostics lists it).
So with the lid closed, "Automatic" still means the island, now as the pill on the external display (§5.2, Q8), and
the Settings label stays "At the notch". Known limit: a notch Mac first launched with its lid already closed reads
false until the built-in display has been seen once. The alternative, a table of hardware model names, was rejected
because it needs updating for every new Mac.

### 3.3 Recorded and derived fixtures

| Fixture | Source | Values |
|---|---|---|
| `mbp14MoreSpace` | **recorded** in the spike | frame 1800 × 1169, visible y 94 h 1036, safe top 38, aux (0, 1131, 790, 38) / (1010, 1131, 790, 38); built in (the spike's only display was the built-in one) |
| `noNotch1080` | constructed | 1920 × 1080 external, visible top inset 25, safe top 0, no aux areas, not built in |
| `safeAreaWithoutAux` | constructed | safe top 38, aux nil → pill (defensive rule) |
| `sideBySide` | constructed | `mbp14MoreSpace` + `noNotch1080` to its left (negative x) and one above (y > 1169) |

Fixtures for a 16-inch panel and other scaled modes are **not** recorded yet. The plan adds the display geometry to
Copy Diagnostics, so the owner's QA run (§10, row Q15) produces them; they are added as recorded fixtures then. No
test asserts a 16-inch value until it is recorded.

### 3.4 Layout (pure)

| Surface | Notch display | Display without a notch (pill) |
|---|---|---|
| `collapsed` | housing plus a 6 pt shoulder each side, plus a 24 pt tab below it: 232 × 62 pt on the recorded display; top edge flush with the display top; bottom corners radius 12 pt, top corners square. Content goes in the tab, the band under the housing (220 × 24 pt): icon left, count text in the middle, ring or stepped glyph right | 200 × 28 pt capsule, centred, top 6 pt under `visibleFrame.maxY` |
| `toast` | width 360 pt, height housing + 36 pt; the text row sits below the housing. While shown (≤ 4 s, longer only while held) it covers 70 pt of the menu bar on each side of the housing; accepted because it is short | 360 × 40 pt, same top as the pill |
| `expanded` | width 380 pt (today's 360 pt card plus 10 pt sides), height housing + content height, at most 320 pt; bottom radius 22 pt | 380 pt wide, height = content, at most 320 pt; all corners 22 pt |

Every frame is centred on the housing (or on the display's mid x for the pill) and clamped inside the display frame.
`IslandLayout.display(for:in:)` picks the display that contains the drop point (half-open edges, as `Rect2D.contains`),
else the first display, which is the same rule as `PanelPlacer` and `HUDLayout.screen(for:in:)`.

**Content height.** Only SwiftUI layout knows it: card line counts, the undo reply, wrapped long names, Show Details
and the text size all change it (today's `ActionHUD` and `HUDPanel` measure `hosting.fittingSize`). So the host
measures its content at the fixed width after every content change and sends `contentHeightChanged` to the machine
(§4.2); clients never supply a height. Content taller than the 320 pt cap scrolls inside the card (a vertical scroll
view around the content below the housing; the island itself never grows past the cap).

---

## 4. States, events and timings

### 4.1 Two layers of state

The **island machine** (`ZivletNotchCore`) is generic: it knows surfaces, hover, keyboard, suppression and deadlines,
but not jobs. A **client** says what it wants: nothing, or a request with a resting surface and a hover surface; a
client keeps a request until the person answers when it must (failures). The **Notch HUD board** (`ZivletUI`) is the
HUD client: it turns `BatchSnapshot`s and `ActionResult`s into items, lingers and one request.

```swift
public enum IslandSurface: Sendable, Equatable { case hidden, collapsed, toast, expanded }
public enum IslandClientID: Sendable, Hashable, Comparable { case hud, tray, picker }   // priority: picker > tray > hud
public struct IslandRequest: Sendable, Equatable {
    public let client: IslandClientID
    public let display: UInt32
    public let resting: IslandSurface       // what the client shows without hover: collapsed, toast or expanded
    public let hoverSurface: IslandSurface  // what hover reveals: usually expanded
}
```

The request carries no content height: the host measures it (§3.4) and tells the machine. It has no "sticky" flag
either (the first design had one): a failure now rests small (§4.3), and "stays until closed" is the client's rule,
which keeps its request until the person closes, retries or undoes.

Only `.hud` is used in M5a. The arbiter takes every client's latest request per display and passes the highest
priority one to the machine; a lower one is kept and returns when the higher one withdraws (the tray during a drag
wins over the HUD; the HUD returns after).

### 4.2 Machine events and transitions

| From | Event | To | Effect |
|---|---|---|---|
| any | `request(nil)` (client has nothing) | `hidden`; during a drag from the island, at `dragEnded` | order out after the fade; clear timers |
| `hidden` | `request(r)` | `r.resting` | order front without activating; grow from the housing (D-N5) |
| `collapsed` or `toast` | `pointerEntered` | same, hover = intent | deadline now + **150 ms** (hover intent) |
| hover intent | `tick` past the deadline | `r.hoverSurface` | expand |
| hover intent | `pointerExited` before the deadline | unchanged | cancel the deadline (a pointer passing on its way to the menu bar opens nothing) |
| `expanded` (from hover) | `pointerExited` | expanded, hover = leaving | deadline now + **300 ms** (grace) |
| leaving | `pointerEntered` | expanded | cancel the deadline |
| leaving | `tick` past the deadline | `r.resting` | collapse, unless still held (focus, drag) or opened by `expandRequested` |
| any visible | `request(r′)` with a new resting surface | `r′.resting`, unless held (a hold keeps `expanded` until it ends) | re-layout |
| any visible | `request(r′)` with the same resting surface (new content) | unchanged | the host re-measures; a new height arrives as `contentHeightChanged` |
| any visible | `contentHeightChanged(h)` | unchanged; hover and hold state unchanged | re-layout at the new height (Show Details, an undo reply) |
| any visible | `wheelShown` | `r.resting` if it was expanded by hover or focus (a toast goes back to the toast); hover ignored | suppressed until `wheelHidden` (W-8) |
| `collapsed` or `toast` | `accessibilityFocused` | `r.hoverSurface` at once (no intent delay) | hold (D-N13) |
| focus-expanded | `accessibilityUnfocused` | as `pointerExited` | grace, then `r.resting` |
| any visible | `expandRequested` (menu command, accessibility action; D-N12) | `r.hoverSurface`; `keyed = true` | the panel becomes key; collapses only on Escape, a close, or the pointer leaving after it entered |
| any visible | `dragBegan` (a drag started in the island) | unchanged | hold: no collapse, no hide until `dragEnded` |
| held by a drag | `dragEnded` | unchanged if the pointer is inside, else grace then `r.resting` | the client restarts its full linger |
| any visible | `clicked` | unchanged; `keyed = true` | the panel may become key (D-M4-16) |
| keyed | `resignedKey` (the person clicked elsewhere) | unchanged | `keyed = false` |
| keyed and `expanded` | `escape` | `r.resting`, or `hidden` and a `close` to the client when the card is closable | resign key |
| any | `reduceMotionChanged(b)` | unchanged | the next transition uses `IslandMotion(reduceMotion: b)` |

Every hold change (hover, accessibility focus, drag) is also an effect `held(Bool)` that the host passes to the
client, which holds or restarts its lingers. Display changes are not machine events: `IslandHosts` owns them (§5.2).
A test runs every event in every state from a table, so a missing row shows up as a failure, not as a gap.

The machine has no clock: every event carries a monotonic `now: Duration` and the effects carry at most one
`deadline`, which the host turns into a single sleep on the same clock that supplies `now` (D-N11). The same pattern as
`LingerTimer`.

### 4.3 HUD board: what each job shows

| Situation | Resting surface | Tab or row (collapsed / toast) | Hover, focus or menu command reveals (expanded) | Leaves |
|---|---|---|---|---|
| One job working | `collapsed` | left: the source file's icon; right: progress ring (the stepped glyph of D-N7 when the length is unknown) | today's working view: "Converting to JPEG", the working line from `HUDCopy.working` (name, percent, time left), bar, Cancel | when the job finishes |
| One job saved | `toast` | "Saved photo.jpg · 2.1 MB → 640 KB" (from `ResultCardModel.sizeLine`) with a check mark; accessibility label "Saved photo.jpg, 2.1 MB to 640 KB" (*new* form: separators spoken as words) | today's result card: thumbnail (drag-out), Undo, Reveal, Open, Copy | after 4 s (`ResultCardModel.successLinger`), held (D-N13); the end of a hold restarts the full 4 s |
| One job failed, or partly failed | `toast` for 4 s, then `collapsed` | toast: the card's title and subtitle from `BatchPresentation` with an error glyph (a shape, not colour alone); then the tab: file icon left, error glyph right | today's failure card: reason, Show Details, Retry, Close | when closed, retried or undone; never on a timer |
| Action done | `toast` | the action's toast ("Copied", "Moved 3 items"), with Undo when the action has one | the same row, larger | 1.5 s, or 4 s with Undo (`ActionHUD.toastLinger`, `undoLinger`), held (D-N13) |
| Action failed or partial | `toast` for 4 s, then `collapsed` | toast: the action card's title with the error glyph; then the tab with the error glyph | today's action card | when closed |
| Two or more items | `collapsed` | left: icon; middle: "3 jobs" (*new*; the 220 pt tab fits it, and "12 jobs"); right: a combined ring over the working items. If any item failed, the error glyph replaces the ring and the accessibility value adds the failed count | a list, failed rows first, one row per item with its own ring or result and its own buttons; at most 5 rows, then "+2 more" (*new*); taller content scrolls (§3.4) | each row by its own rule; the island stays while any failed row is left |

"Saved photo.jpg" is the owner's example and becomes the toast's first words; today's card title stays the card's
title. Every other string comes from `HUDCopy`, `ResultCardModel`, `BatchPresentation` and `ActionResult`, so the
existing copy tests keep covering it. The *new* strings above are Zivlet's own.

A failure does not open a card by itself (the first design did). A failure can arrive minutes after the drop, while
the person types or presents, and a 380 pt card at the top centre would cover the foreground app's toolbar and take its
clicks until closed. It shows as a toast, is announced with high priority (§5.5), and then waits in the tab until the
person looks. Several failures do not stack cards: they are rows of the list.

Done and toast states go to `hidden` when no item is left. A result that arrives while the island is held does not
collapse it.

### 4.4 Timings in one place

| Name | Value | Source |
|---|---|---|
| hover intent | 150 ms | spike default, tuned by owner row Q1 |
| hover grace | 300 ms | spike default |
| success linger | 4 s, held (D-N13) | `ResultCardModel.successLinger` (P1-41) |
| action toast | 1.5 s; 4 s with Undo | `ActionHUD` (03b §7) |
| toast lingers with VoiceOver or Switch Control running | three times the above (12 s, 4.5 s, 12 s) | D-N13 |
| failure toast, then the tab | 4 s, then until closed | P1-41 (until closed) |
| expand / collapse | spring 0.38 / 0.78 and 0.32 / 0.9 | S6 |
| Reduce Motion | 0.18 s cross-fade | S7 |
| drop → island visible | ≤ 50 ms | P1-40's HUD budget, signpost `drop→island` |
| hover → first frame | ≤ 50 ms (warm 17–22 ms measured) | S6 |

---

## 5. Rules

### 5.1 The wheel wins (W-8)

The wheel's panel is at `.popUpMenu`, the island at `.statusBar`, so the wheel draws over the island and gets every
drag and click that lands on both. While the wheel is visible, the app sends `wheelShown`: an island expanded by
hover or focus goes back to its resting surface (a toast to the toast), and hover is ignored until `wheelHidden`. An
island opened by the menu command stays (it is not under the pointer's control), but it is below the wheel. In M5b the
tray never accepts a drop while the wheel is open.

### 5.2 Displays

- A job's island is on the display where its drop happened (the drop point from `DropIntake`, as today's
  `ResultHUD.prepare(near:)` gets it). Actions use their drop point the same way.
- Each display has its own host and its own items; "3 jobs" counts the jobs on that display.
- **`IslandHosts` alone owns display changes.** The machine knows no displays, and a host's geometry is not fixed at
  creation. On each change from the provider, `IslandHosts` (1) destroys the hosts of displays that are gone, (2)
  calls `host.update(display:)` on the hosts that remain, which re-lays out the current surface (a scaled-mode
  switch, an arrangement change or a menu-bar move keeps the display ID but changes the geometry), (3) creates and
  pre-warms hosts for new displays (D-N8), and (4) tells each client the new display set with the ID of the display
  that replaces each removed one (the first display). The client moves its items (for the HUD,
  `board.movingItems(from:to:)`) and re-issues its requests.
- A display that disappears therefore hands its items to the first display. A closed lid is expected to remove the
  built-in display from `NSScreen.screens`, so its items go to the pill on the external display, and
  `hasBuiltInNotch` stays true (§3.2), so "Automatic" keeps the island (not tested in the spike; owner row Q8).
- With "Displays have separate Spaces" off, a secondary display has no menu bar; the pill still sits 6 pt under
  `visibleFrame.maxY`, which is then near the top edge.

### 5.3 Menu bar, full screen and Spaces

- The island never moves, hides or reveals the menu bar. It is visible only while a client has a request.
- In a full-screen Space on a notch display, the strip beside the camera is black and the collapsed island sits in it
  (S4). When the menu bar slides in, the island stays above it.
- **Acceptance rule: the collapsed island never covers more than 6 pt of the menu bar beside the housing** (D-N3).
  macOS fills app menus up to the left edge of the housing and status items up to its right edge, so on a crowded menu
  bar anything wider would cover the last menu title or the leftmost status item and take its clicks for the whole
  job. A toast (seconds) and an expanded card (on hover, focus or the menu command) may cover more while they show.
  Zivlet does not read other apps' window positions to dodge them. Owner row Q13 checks this with a long-menu app.
- The panel joins every Space and stays out of Mission Control's window sweep (`.stationary`) and the window cycle
  (`.ignoresCycle`).
- Stage Manager: a non-activating, stationary panel is not a stage window; owner row Q9 confirms it.

### 5.4 Keyboard and focus

The island never takes focus by appearing, expanding or collapsing (S5). Buttons act without taking the keyboard
(`becomesKeyOnlyIfNeeded`). A click into the card's non-button area (details text) makes it key, as today
(D-M4-16); then Escape collapses an expanded island or closes a closable card, and Tab moves between its buttons.
G-M4-10 applies to the pointer path: Escape works only after such a click.

Without a pointer (D-N12): the status menu (reachable from the keyboard with Control-F8, and by Voice Control and
Switch Control) has "Show Progress and Results" (*new*), which expands the island on the display that has items (the
menu-bar display first) and makes it key, so Tab and Escape work at once. The same menu already has Cancel for each
running batch and Undo for recent results. The island's buttons are ordinary accessibility buttons once expanded, so
Voice Control ("click Retry") and Switch Control reach them. No global shortcut in M5a.

### 5.5 Accessibility

- The panel is one accessibility group labelled "Zivlet progress and results" (*new*). Collapsed, its value is the
  same text the expanded view shows ("Converting to JPEG, photo.heic, 40%, less than a minute left"), so VoiceOver
  users never need hover to read it. Accessibility focus entering the island expands it and holds it, as hover does;
  focus leaving acts as the pointer leaving (`accessibilityFocused` / `accessibilityUnfocused`, §4.2). The toast has
  its own accessibility label with separators spoken as words (§4.3), so VoiceOver does not read "right arrow".
- Toasts are held while accessibility focus is inside and linger three times as long while VoiceOver or Switch
  Control runs (D-N13). Undo stays in the status menu with no time limit.
- Announcements (`NSAccessibility` announcement, from the board): a job starting (medium priority, once per batch),
  a job saved ("Saved photo.jpg", medium), a failure (the card's title, high), an action toast (its text, medium).
  Progress percentages are not announced.
- Buttons keep today's titles and labels; the drag-out thumbnail keeps its label from `ResultCard`.
- Contrast: D-N10 for text. Non-text: the ring's fill is white and its track white at 0.4, so the fill is 21:1
  against the black island and about 5.7:1 against the track, and the track is about 3.7:1 against black, all above
  the 3:1 that WCAG 1.4.11 asks; the error glyph is white on black and differs from the check mark by shape. Text sizes stay
  those of today's HUD (headline, callout, caption).
- Reduce Motion: D-N5. Reduce Transparency: no change (the island is opaque). Increase Contrast: D-N10 outline.

### 5.6 Privacy

The island shows file names at the top centre of the display, where a shared screen shows them, as today's card does
near the drop. No new data leaves the Mac. The privacy notes get one line.

---

## 6. Settings

`ZivletSettings` gains one group, stored as `settings.hud.v1` like the others:

```swift
public enum HUDPlacement: String, Sendable, Codable, CaseIterable { case automatic, notch, nearDrop }
public struct HUDGroup: Sendable, Equatable, Codable { public var placement = HUDPlacement.automatic }
extension HUDPlacement {
    /// Where results show on this Mac: automatic means the notch on a Mac with a built-in notch display.
    public func resolved(hasBuiltInNotch: Bool) -> HUDPlacement
}
```

- **Migration.** An M4 store has no `hud` key; it loads as `.automatic`, so a notch Mac gets the Notch HUD and any
  other Mac keeps today's card (OWN-HUD-1 defaults). Nothing is written until the person picks. A stored value that
  does not decode falls back to `.automatic` with the existing one-line error. No other group changes, so no
  migration of stored data is needed; the test is that an M4-shaped defaults domain loads unchanged plus the new
  default.
- **Settings › General**, section "Progress and results" (*new*): picker "Show progress and results:" with
  **At the notch** (on a Mac without a notch: **At the top of the screen**) and **Near the drop**. The selection shows
  the resolved value; choosing one stores it explicitly.
- **OWN-HUD-2 resolved (2026-10-23):** the owner chose the two labels above. "Near the drop" keeps today's card
  below and to the right of the drop point (`HUDLayout`); there is no fixed bottom-right corner.
- A change applies to jobs and actions that start afterwards; what is on screen stays where it is.
- `hasBuiltInNotch` is the latch of §3.2, not "a notch display is connected now".
- The demo's launch argument `-ZivletHUDPlacement notch|nearDrop` never enters `SettingsStore`: like
  `-ZivletRevealResults`, it is read by the app's `SettingsWiring`, and routing uses
  `override ?? settings.hud.placement`. So the picker and `diagnosticsJSON` show only what the person chose, and
  choosing the value that equals the override is still saved.
- `Settings.diagnosticsJSON` includes the group.

---

## 7. Reusing today's HUD

| Today (M4, `ZivletUI/HUD`) | In the Notch HUD |
|---|---|
| `HUDCopy`, `BatchPresentation`, `ResultCardModel` (buttons, linger, size line), `LingerTimer`, `CardState`, `UndoReply` | used as they are; the board composes them |
| `ResultCard`, `ResultHUDView.working`, `ActionHUDView` | split into surface-free content views (`ResultCardContent`, `WorkingContent`, `ActionContent`) and today's wrappers that add `.hudGlass()` and the 360 pt frame. The island wraps the same content in black with the dark colour scheme forced. Behaviour-preserving; today's tests stay green |
| `FileDragSource`, `ThumbnailLoader` | used as they are inside the expanded card and the list rows |
| `ResultHUD`, `ActionHUD` | keep working for "Near the drop"; both conform to new `HUDPresenter` / `ActionPresenter` protocols so the wiring can pick per drop. `ResultHUD`'s Retry no longer queues its own anchor: it reports the source batch and anchor, and the wiring routes the new batch (plan N11) |
| `HUDBoard` (Runtime) | the Notch HUD board keeps its own items, but takes the same `BatchSnapshot`s |

The press handlers (Undo, Reveal, Open, Copy, Retry, Cancel, Close) are the same closures `ConversionWiring` and
`ActionWiring` already give the HUDs, so no wiring logic is duplicated.

**Who owns each batch.** Snapshots arrive by `BatchID` on one stream, but the placement is chosen per drop, and
`convert()` returns the ID asynchronously, so the first snapshot can arrive before any mapping exists.
`ConversionWiring` therefore keeps a FIFO of pending routes (drop point, drop time, route) consumed by the first
snapshot of an unknown `BatchID`, then a `[BatchID: Route]` map for every later snapshot. Only then does it call the
routed presenter's `prepare(near:)` and `show`, so each presenter's own anchor FIFO stays in step. Retry from either
presenter goes through the wiring, which enqueues the source batch's route. A batch or announcement with no drop
(status-menu undo, a batch nobody prepared) takes the current resolved placement. The FIFO assumes batches start in
the order they were submitted, as `ResultHUD` already assumes today.

---

## 8. How the notch Drop Box and the picker plug in later (M5b and the last phase)

| Row | Client | What it adds to the shared infrastructure | Needs from M5a |
|---|---|---|---|
| P2-141 shelf core | none (pure `ZivletShelfCore`) | `Shelf`, `ShelfItem`, `boxes.json`, shake detector | nothing |
| P2-55 Drop Box panel | none (a separate floating panel in `ZivletActions`) | the expanded box, dock, grid and list | nothing |
| P2-142 bulk actions | none | Share, AirDrop, Copy, Move/Copy to, Zip, Convert all | nothing |
| P2-143 notch tray | `.tray` in `ZivletActions`, registered with the same `IslandHosts` instance that `AppDelegate` injects into the Notch HUD | a pure `NotchProximity` detector in `ZivletTrigger`, fed by the drag sampler (no permission); a `dropTarget` resting surface; the panel registers for file drags only while the tray asks for `dropTarget`; the compact box view as the tray's expanded content | `IslandArbiter` priority (tray > HUD), `IslandLayout` per display, the host's frame and motion rules, `wheelShown` suppression |
| Picker at the notch (last phase) | `.picker` in `ZivletWheel` | a Bar or Wheel picker drawn as the island's expanded content during a drag-pick | priority picker > tray > HUD; the same panel level would put it under the wheel, so the picker raises its host's level while it shows |

Design constraint for M5a: nothing in `ZivletNotchCore` or `ZivletNotch` may name jobs, batches or files. The host
takes a SwiftUI view per surface from its client and a request; the core takes requests and events. The arbiter and
the client enum are tested with three fake clients in M5a, so M5b adds clients, not branches.

---

## 9. Verification approach

- Pure tests: geometry with the recorded fixture, layout per surface and display, every transition in §4.2 with an
  injected clock, arbiter priority and hand-back, board items and lingers per row of §4.3, settings defaults and
  migration.
- Shell tests (as `HUDTimingTests` does today, with displays placed off screen at −5000): panel configuration (level,
  behaviour, style mask, key rules), frame swap on expand and collapse, ordered out when hidden with no pending task,
  stale completions with a non-instant motion (show → hide → show and collapse → expand leave the panel visible at
  the newest frame), the shape-sized tracking area and the pointer check after a frame change with a fake pointer
  location, display removal and geometry change under the same ID, a host per display pre-warmed at launch, and
  drop → island ≤ 50 ms measured from before `show` to a visible panel at the expected frame.
- Automated in the exit run: `make test lint coverage app release-check licence-gate`; a Debug-app demo that converts
  with the notch placement and captures the island; the TCC check counting `preflight=no` requests attributed to
  Zivlet (S11); idle-CPU samples of the Debug app, each compared with a baseline sample of the same build with no
  island (plan X6).
- Owner QA: §10.

---

## 10. Owner QA rows (real hardware)

| Row | Check |
|---|---|
| Q1 | Real notch: a pointer that crosses the notch on its way to the menu bar opens nothing; resting on it opens after about 150 ms; leaving collapses it. Tune the intent delay if needed. Then the frame-swap cases of D-N6, each a separate result: (a) moving near the shape while it collapses does not re-open it; (b) a collapse that shrinks the frame under a still pointer leaves no stale hover (moving away afterwards and coming back opens it normally); (c) an island that appears under a resting pointer opens after the intent delay without the pointer moving; (d) re-entering during a collapse re-opens it unclipped |
| Q2 | Cancel, Undo, Reveal, Open and Copy in the island do not take focus from the app being typed in |
| Q3 | A click into the details, then Escape, closes the card (G-M4-10) |
| Q4 | The result thumbnail drags out of the island into Finder, Mail and Messages; the island stays open for the whole drag, even a slow one past 4 s, and its toast lingers the full 4 s after the drop |
| Q5 | Full screen (Safari, Keynote, a full-screen video): the island shows in the black strip; the menu bar slides in under it without being blocked |
| Q6 | Menu bar set to hide automatically on the desktop: the island neither reveals nor blocks it |
| Q7 | External display without a notch: a drop there shows the pill on that display; a drop on the built-in display shows the island there |
| Q8 | Lid closed with an external display: the pill on the external display |
| Q9 | Stage Manager on: the island stays put and is not a stage window |
| Q10 | Switching Spaces and Mission Control: the island stays and does not animate away |
| Q11 | VoiceOver: start, saved, failed and toast announcements; the collapsed island reads its full text and the toast its spoken form ("2.1 MB to 640 KB"); focus expands it and holds it; moving focus away collapses it; toasts last three times as long |
| Q12 | Reduce Motion (fade only), Increase Contrast (outline), Reduce Transparency (no change) |
| Q13 | Crowded menu bar (many status items, an app whose menus reach the notch): the collapsed island covers no menu title or status item and never blocks a click on one; a toast may cover them for its few seconds. Record a screenshot for OP-6 |
| Q14 | Screen sharing or recording: what the island shows is acceptable |
| Q15 | 16-inch MacBook Pro and two more scaled modes: Copy Diagnostics → display geometry, recorded as fixtures |
| Q16 | Settings: switching between "At the notch" and "Near the drop" affects the next job only |
| Q17 | 120 Hz: the expand spring looks smooth; no dropped frames visible |
| Q18 | Keyboard only (no pointer): Control-F8 to the status menu, "Show Progress and Results" opens the island with keyboard focus; Tab reaches Cancel, Undo, Reveal, Open, Copy and Retry; Escape closes it; Cancel and Undo also work from the status menu |
| Q19 | Voice Control: "Show Progress and Results" through the menu, then "click Undo" and "click Retry" in the island |
| Q20 | Switch Control: reach the island through the status menu or its accessibility action, press Undo before the toast leaves (toasts last three times as long while Switch Control runs) |
| Q21 | A failure while typing in another app: a toast and then the tab with the error glyph, no card, no focus change; hover opens the card with Retry |
| Q22 | Sleep the Mac while a toast shows; on wake the toast is gone, a failure tab is still there (D-N11) |

---

## 11. Risks

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Accidental opens when the pointer heads for the menu bar | medium / medium | 150 ms intent delay, collapse on exit after 300 ms; Q1 tunes it |
| The island covers menu items next to the notch | high for 38 pt ears (macOS lays menus and status items out up to the housing) / medium; low with the tab | D-N3: 6 pt shoulders and content in a tab below the housing; acceptance rule in §5.3; Q13; owner point OP-6 |
| Apple changes notch metrics or how full-screen Spaces treat panels | low / high | public API only, no hard-coded sizes, defensive pill rule; the "Near the drop" card stays a Settings choice |
| A failure card at the top centre covers the foreground app | medium / medium | a failure no longer opens a card by itself: a toast, then the tab (§4.3); the card opens only on hover, focus or the menu command |
| Stale animation completions order out or clip a live island | high without a guard / high | D-N4 generation token; host tests with a non-instant motion |
| Hover misfires around frame swaps (re-expand loops, stale inside, no enter under a resting pointer) | medium / medium | D-N6 shape-sized tracking area and pointer check after each frame change; Q1 (a)–(d) |
| Keyboard, Voice Control and Switch Control users cannot reach the island's buttons | high without D-N12 / high | status-menu command, accessibility action, longer lingers; Q18–Q20 |
| Progress redraw cost on long jobs | low / low | D-N7 throttle; exit check samples CPU |
| Only one display mode recorded | high / low | derived values are labelled; Q15 records more before 0.5 |
| Hover not verified by the spike | medium / medium | owner row Q1 before 0.5; M4's HUD hover in the same kind of panel works |
| Name collision: 05 §9.2 uses M5a for all of beta 0.5 | certain / low | the plan states both meanings; open point for the owner (plan §7) |

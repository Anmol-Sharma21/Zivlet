# 14 — App Platform & Architecture (macOS 26+, unsandboxed, Developer ID)

Status: design deliverable (platform track). Date: 2026-10-20.
Inputs: [00-decisions](00-decisions.md), plus Zivlet's internal product spec, platform-feasibility notes (written for a sandboxed MAS app on macOS 13, so parts are superseded here) and competitive notes (not published).

Locked constraints (from 00-decisions): free and open source (GPLv3-compatible), direct download, notarized Developer ID, **not sandboxed**, **macOS 26+ only**, Apple silicon first, Swift 6 + SwiftUI/AppKit, Sparkle 2 updates, no analytics. Zivlet is a clean-room implementation: no code from the reference app or from Open-Tangerine is ever copied.

## Evidence legend

| Label | Meaning |
|---|---|
| **OBSERVED** | Seen directly: Apple docs, package source or releases, or a local probe run on the dev machine (macOS 27.0 build 26A428, Swift 6.4, M-series). |
| **INFERRED** | Reasoned from observed facts. Not verified at runtime. |
| **SPIKE** | Must be proven by the named spike in §9 before we rely on it. |

Local probes (`poll.swift`, `tap.swift`) are a local prototype, not published. Note that they ran on macOS 27, not 26.

---

## 0. TL;DR

| Area | Decision |
|---|---|
| Trigger | **Hybrid, permission-free.** Global `NSEvent` *mouse* monitors (`leftMouseDown/Dragged/Up`, no permission needed) wake us when a drag starts, so polling costs nothing at idle. While a file drag is live, sample `NSEvent.modifierFlags`, the mouse button and `NSPasteboard(name: .drag).changeCount` once per display frame (120 Hz on ProMotion). Optionally add a listen-only `flagsChanged` event tap, which on macOS 27 is created **without** a TCC prompt (OBSERVED probe; SPIKE S-T2 for whether events arrive). Input Monitoring and Accessibility are never required. A `CGEventTap` that needs Input Monitoring is used only for an opt-in "Esc closes the wheel" mode. |
| Overlay | Borderless `NSPanel` with `.nonactivatingPanel`, level `.popUpMenu`, and behaviour `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .stationary, .ignoresCycle]`. Pre-warmed at launch. An AppKit `NSView` is the drag destination and does the polar hit-testing. SwiftUI draws the wheel with `GlassEffectContainer`, `glassEffect(_:in:)` on custom `Shape` petals, and `glassEffectID` morphing between modes. Highlight is driven from the model, not from `.interactive()`, because pointer events never reach our window during someone else's drag. |
| Shell | AppKit lifecycle (`NSApplication` + `AppDelegate`, `LSUIElement`). `NSStatusItem` + `NSMenu`. Settings and onboarding are AppKit windows hosting SwiftUI. `SMAppService.mainApp` for launch at login. Sparkle **2.10.0** with EdDSA. The appcast lives on GitHub Pages and the DMG and deltas on GitHub Releases. CI runs on GitHub Actions `macos-26` (arm64): sign helpers inside-out with the hardened runtime, `notarytool --wait`, staple. |
| Extensibility | App Intents (Shortcuts, Spotlight actions on 26), a Services menu entry (keyboard path with **zero permissions**), a `zivlet` CLI in the bundle (installed by Homebrew cask `binary` or "Install CLI"), and a limited `zivlet://` URL scheme. A global hotkey can use the Finder selection through Apple Events, but only after an explicit **opt-in** (one Automation prompt). Finder Sync context menu in P1. Foundation Models "say what you want" field in P2, optional. |
| Structure | A thin Xcode project (app, CLI, extensions, synchronized folders, xcconfigs) plus a local Swift package `ZivletKit` with modules `ZivletCore`, `ZivletEngines`, `ZivletRuntime`, `ZivletTrigger`, `ZivletWheel`, `ZivletUI`. Swift 6 language mode. UI modules use `defaultIsolation(MainActor.self)`. Engines are nonisolated. `actor JobScheduler` with per-resource lanes (bounded width). `swift-subprocess` **1.0.2** for process spawning, with graceful teardown on cancel. Swift Testing for unit, golden and matrix tests. XCUITest only for windows. |

---

## 1. Drag + modifier trigger

### 1.1 Requirements

1. Detect "a file drag is in progress" system-wide: Finder, the Desktop (also Finder), Mail attachments, browsers, Photos, Electron apps, and shelves like Dropover and Yoink.
2. Detect a **tap** of a configured modifier (Zivlet defaults: ⇧ convert, ⌘ tools, ⌃ actions) during that drag, and switch wheels on another tap.
3. Show the wheel at the cursor within **one frame** (Zivlet target: p95 ≤16 ms on an M1 Air).
4. No Accessibility, Input Monitoring or Screen Recording prompt in the default flow (00-decisions principle).
5. Close to zero idle CPU and wakeups. This app runs all day.

### 1.2 Candidate mechanisms

| Mechanism | Permission (macOS 26/27) | Latency (tap → known) | Idle cost | Reliability notes |
|---|---|---|---|---|
| **A. Pure polling**: a `DispatchSourceTimer` at 10 Hz idle and 60 Hz active reads `NSEvent.modifierFlags`, `CGEventSourceFlagsState`, `CGEventSourceButtonState`, `NSEvent.pressedMouseButtons`, `CGEventSourceKeyState(kVK_Escape)` and the drag pasteboard `changeCount` / `availableType` | None for modifiers, buttons and the pasteboard. **`CGEventSourceKeyState` for non-modifier keys (Esc) is filtered without Input Monitoring.** It silently returns false, so Esc never works for most users (INFERRED) | Uniform 0–16.7 ms at 60 Hz (mean 8.3 ms), plus the render frame. **Cannot meet p95 ≤16 ms end to end at 60 Hz.** At 120 Hz: 0–8.3 ms | 10 wakeups/s forever. Measured cost per tick ≈ 10 µs of work (p50) and ≈ 35–50 µs including the wakeup (OBSERVED probe, table below) | Very robust. Independent of which app is the drag source. Pasteboard reads are types-only. |
| **B. `NSEvent.addGlobalMonitorForEvents`** for mouse events (`.leftMouseDown/.leftMouseDragged/.leftMouseUp`) | **None.** Apple: only *key-related* events need Accessibility (OBSERVED Apple docs) | Event-driven (<1 ms after the window server dispatch) | Zero wakeups when the mouse is idle. One callback per mouse event while dragging | Expected to receive drag events while another app owns the drag session (SPIKE S-T1 confirms). It does not see events aimed at our own windows (a local monitor covers those). |
| **B'. Global monitor for `.flagsChanged`** | Apple's docs class "key-related" events as needing Accessibility. In practice modifier changes are widely reported to arrive without it. **SPIKE S-T2** | Event-driven | Zero | If it works, it gives modifier edges without polling. |
| **C. `CGEventTap`, listen-only, `cgSessionEventTap`** | Probe on macOS 27 (OBSERVED, `tap.swift`, with `CGPreflightListenEventAccess() == false`): mask `leftMouseDragged|leftMouseUp` → **created**. Mask `flagsChanged` → **created**. Mask `keyDown` → **nil (denied)**. So keyboard taps need Input Monitoring. Mouse and flags taps can be created without it. Whether the flags tap is actually delivered events without permission is **SPIKE S-T2** | Event-driven, ~sub-ms | Zero | Runs on a CFRunLoop source. Must handle `tapDisabledByTimeout`. Keyboard (Esc) needs Input Monitoring, which brings the system prompt and a System Settings toggle. |
| **D. Carbon `RegisterEventHotKey`** | None for normal combos. In sandboxed apps, Sequoia rejects combos whose only modifiers are ⌥/⇧ (error −9868); reports say unsandboxed apps are unaffected (forum thread, Shottr KB). **Unmodified Esc is SPIKE S-T3** | Event-driven | Zero | Consumes the key. Useful for **Esc only while the wheel is visible** (register on show, unregister on hide). This would close the wheel and let the drag continue instead of Finder cancelling it. |
| E. IOHIDManager | Input Monitoring | — | — | No benefit over C. Rejected. |
| F. Accessibility (`AXObserver`, `AXUIElement`) | Accessibility (a scary prompt) | — | — | Not needed for the trigger. Rejected. |

**Probe results** (OBSERVED, `poll.swift` reads all of mechanism A's APIs plus `NSEvent.mouseLocation` each tick, for 10 s, `-O`):

| Interval | Ticks | Process CPU over 10 s (includes ≈0.03 s of process start-up) | Tick work p50 / p99 |
|---|---|---|---|
| 100 ms (10 Hz) | 101 | 0.040 s (0.40 %) | 13.6 µs / 74.8 µs |
| 16 ms (60 Hz) | 624 | 0.059 s (0.59 %) | 10.8 µs / 62.2 µs |
| 8 ms (120 Hz) | 1244 | 0.097 s (0.97 %) | 10.3 µs / 118 µs |

The marginal cost is about 50 µs of CPU per tick including the timer wakeup. Polling at **120 Hz costs ~0.6 % of one core, and only during a drag**. At 10 Hz idle it is ~0.05 % of a core, but it is a permanent 10 Hz wakeup, which shows up in Activity Monitor's Energy tab and blocks deep idle. That is the case for using event-driven wake-up at idle.

### 1.3 Recommended design: hybrid "event-woken, frame-sampled"

```
idle ──(global leftMouseDown)──▶ armed: snapshot drag changeCount
armed ──(leftMouseDragged && changeCount > snapshot && hasFileTypes)──▶ live: start frame sampler
live  ──(modifier rising edge == wheel mask)──▶ wheel(mode) visible
wheel ──(other mask rising edge)──▶ switch mode (in-place morph)
wheel ──(same mask tapped again | drop | button up | Esc (opt-in) | Space change)──▶ hidden
any   ──(button up)──▶ idle (stop sampler)
```

1. **Idle: zero polling.** Install a global and a local `NSEvent` monitor for `[.leftMouseDown, .leftMouseDragged, .leftMouseUp]`. On `leftMouseDown`, snapshot `NSPasteboard(name: .drag).changeCount`. On the first `leftMouseDragged` after that, compare the count. If it advanced, check **types only**: `dragPB.availableType(from: fileTypes)` where `fileTypes = [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map(NSPasteboard.PasteboardType.init)`. Never read URLs or data mid-drag.
2. **Live: frame-synced sampler.** Use `NSScreen.displayLink(target:selector:)` (macOS 14+) for the screen under the cursor. It ticks at the display's refresh rate (120 Hz ProMotion, 60 Hz most externals). Each tick reads `NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)`, `NSEvent.pressedMouseButtons & 1`, `dragPB.changeCount` and `NSEvent.mouseLocation`. Sampling on vsync means a modifier press seen on frame N renders the wheel on frame N+1, which keeps the worst case ≤2 frames (≤16.7 ms at 120 Hz). If S-T2 shows `flagsChanged` arrives without permission, the event handler feeds the same reducer immediately and the display link only reconciles.
3. **Watchdog.** If a `leftMouseUp` is missed (for example the drop lands in our own window, or a system modal takes over), the sampler sees the button up and finishes. A 2 Hz `pressedMouseButtons` check runs only while "armed" or "live".
4. **Tap semantics.** Show on the **rising edge** (key down) for latency. Do not wait for key release, and keep the wheel open after release so the user can keep dragging. Ignore modifiers that were already held when the drag started (for example a ⌘-move drag in Finder), and accept only the *exact* configured mask (no extra modifiers). Debounce edges within 40 ms of the drag starting.
5. **Cancel without permissions** (the default):
   - tap the **same** modifier again to close (new; zero-permission);
   - drop on the **hub**: `performDragOperation` returns `false`, so Finder animates the icon back;
   - releasing anywhere else is a normal drop handled by whatever window is under the cursor.
   - Esc via a Carbon hotkey registered only while the wheel is visible (SPIKE S-T3). If that fails, offer the opt-in "Esc closes wheel (needs Input Monitoring)" toggle, which uses a listen-only `keyDown` tap.
6. **Space and Mission Control changes.** Hide on `NSWorkspace.activeSpaceDidChangeNotification`.

Pure, testable core (the AppKit sampler only produces samples):

```swift
// ZivletTrigger/TriggerMachine.swift — no AppKit imports; unit-tested with recorded traces
public struct InputSample: Sendable, Equatable {
    public var uptime: TimeInterval
    public var modifiers: ModifierMask          // ⌃⌥⇧⌘ bits only
    public var primaryButtonDown: Bool
    public var dragChangeCount: Int
    public var dragHasFiles: Bool               // types-only check, evaluated when changeCount moves
    public var location: CGPoint                // global, bottom-left origin
}

public enum TriggerEffect: Sendable, Equatable {
    case show(WheelMode, at: CGPoint)
    case switchTo(WheelMode)
    case hide(HideReason)
}

public struct TriggerMachine: Sendable {
    public var bindings: [WheelMode: ModifierMask]
    private var phase: Phase = .idle
    private var previous: ModifierMask = []
    private var heldAtDragStart: ModifierMask = []

    public mutating func step(_ s: InputSample) -> [TriggerEffect] { /* pure state transitions */ }
}
```

### 1.4 Behaviour by source and context

| Context | What the trigger sees | Handling |
|---|---|---|
| Finder windows and the Desktop | `public.file-url` on the drag pasteboard. Finder runs the drag loop, so global mouse monitors fire | Primary path. Note Finder's operation-mask rules (⌘ = move, ⌥ = copy): return `.copy` when allowed, otherwise `.generic`. Spring-loaded folders are unaffected because the wheel covers only a 300–360 pt disc. |
| Mail attachments, Photos, Safari images | **File promises** (`NSFilePromiseReceiver.readableDraggedTypes`), often with no file URL | Count promises as "has files". At drop, `receivePromisedFiles(atDestination:)` into a staging folder. Since there is no "original folder", output goes to `~/Downloads` (a setting), revealed in the result card. SPIKE S-T5 covers Chrome, Arc and Firefox behaviour. |
| Browsers dragging links or text | `public.url` / `public.utf8-plain-text` only | Ignored (not a file drag). |
| Electron apps (VS Code, Slack) | Usually `public.file-url` | Same as Finder. |
| Dropover / Yoink shelves | Their own panels at `.floating` or similar. Their drags carry file URLs | Our level `.popUpMenu` (101) sits above them. Shake (Dropover) and modifier taps don't collide. A per-app ignore list exists in Settings. |
| Drags from our own windows (Float shelf, result card) | A local monitor sees them | Allowed, so a result can be converted again. |
| Multi-display | `NSEvent.mouseLocation` is global | Pick the screen with `NSMouseInRect(loc, $0.frame, false)` and attach the display link to that screen. The wheel opens centred on the cursor and stays put if the cursor crosses displays. Do **not** clamp the centre to `visibleFrame`. Instead, rotate or compact the petal layout at screen edges so the slice under the cursor stays reachable (SPIKE S-W3 for feel). |
| Full-screen Spaces | — | `.fullScreenAuxiliary` + `.canJoinAllSpaces` + `.nonactivatingPanel` in an `LSUIElement` app shows over another app's full-screen Space (INFERRED; S-W2 covers a full-screen app). |
| Secure input (password fields) | Modifier flags are still readable | No change. We never read keys. |

### 1.5 Verdict

Use the **hybrid**. It keeps pure polling's strongest property (no prompts) and fixes its two weaknesses: permanent 10 Hz polling and 60 Hz-quantised latency. It also adds a working, permission-free cancel. `CGEventTap` keyboard access (Input Monitoring) is opt-in only, for Esc.

---

## 2. Overlay wheel

### 2.1 Panel

```swift
final class WheelPanel: NSPanel {
    var keyboardMode = false                                   // §4.6 keyboard flow
    override var canBecomeKey: Bool { keyboardMode }
    override var canBecomeMain: Bool { false }

    init(diameter: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu                                     // 101, above shelves and the Dock
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                              .transient, .stationary, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true; isMovable = false
        animationBehavior = .none                              // SwiftUI owns the intro animation
    }
}
```

- **Pre-warm.** At launch, create the panel, its `NSHostingView` and the glass container. Order it front at `alphaValue = 0` off-screen for one frame, then order it out. The first real show then involves no view construction or shader compilation, only `setFrameOrigin` + `orderFrontRegardless()` + a model change. Measure with `OSSignposter` from the sample timestamp to the first `CATransaction` commit after show.
- A **nonactivating** panel never activates our app during a drag, so Finder keeps focus and its drag loop is undisturbed. In keyboard mode it can become key **without activating the app** (that is what `.nonactivatingPanel` permits). Arrow, Enter and Esc then reach us while Finder stays the active app.

### 2.2 Drop target during an external drag

- The content view is `WheelDropView: NSView`, registered with `registerForDraggedTypes(fileTypes)`. The `NSHostingView` is a subview **with no SwiftUI drop modifiers**, so AppKit walks up to `WheelDropView` as the destination. That gives us exact control of `NSDraggingInfo`.
- A window ordered in under a stationary cursor mid-drag becomes the destination at the next drag event. The user always moves toward a slice, so this is fine.
- `draggingUpdated(_:)` fires on every mouse move (and periodically). The hit-test is polar: `v = location − centre`, `r = |v|`, `θ = atan2`. If `r < hubRadius`, the target is the hub (cancel). If `hubRadius ≤ r ≤ outerRadius + slack`, then `slot = floor((θ − θ₀) / sector)`. Beyond that, keep the last highlight for 120 ms (hysteresis) to avoid flicker at gaps.
- `performDragOperation(_:)`:
  - Read `readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`, or `[NSFilePromiseReceiver.self]` for promises.
  - Hand the work to the scheduler and **return within ~1 ms**, because the Finder drag animation waits on it.
  - The hub returns `false`.
- Petals are computed provisionally from the UTI of the first file-URL *type* (no data reads). They are refined on `draggingEntered` when reading URLs is cheap.

### 2.3 Rendering: Liquid Glass (macOS 26 SwiftUI)

All of these APIs are OBSERVED on developer.apple.com with availability macOS 26.0+:
- `glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`
- `GlassEffectContainer(spacing:content:)`. Per Apple, it renders all glass shapes in one pass ("improving rendering performance") and lets them blend and morph.
- `glassEffectID(_:in:)` with a `@Namespace`
- `glassEffectUnion(id:namespace:)`
- `glassEffectTransition(_:)` with `GlassEffectTransition` (`.matchedGeometry`, among others)
- `Glass.regular / .clear / .identity`, `.tint(_:)`, `.interactive(_:)`

```swift
struct PetalShape: Shape {
    var start: Angle, end: Angle, inner: CGFloat, outer: CGFloat, gap: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(start.radians, end.radians), .init(inner, outer)) }
        set { start = .radians(newValue.first.first); end = .radians(newValue.first.second)
              inner = newValue.second.first; outer = newValue.second.second }
    }
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // constant-width gaps: inset each edge by gap/2 converted to an angle at that radius
        let dOut = Double(gap / 2 / outer), dIn = Double(gap / 2 / inner)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: .radians(start.radians + dOut),
                 endAngle: .radians(end.radians - dOut), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .radians(end.radians - dIn),
                 endAngle: .radians(start.radians + dIn), clockwise: true)
        p.closeSubpath()
        return p          // corner rounding: replace the joins with addArc(tangent1End:tangent2End:radius:)
    }
}

struct WheelView: View {
    @Bindable var model: WheelModel          // @Observable, @MainActor
    @Namespace private var glass
    var body: some View {
        GlassEffectContainer(spacing: 6) {
            ZStack {
                ForEach(model.slots) { slot in
                    let hot = model.highlighted == slot.id
                    PetalLabel(slot: slot, highlighted: hot)            // SF Symbol + caption at the polar centre
                        .frame(width: model.diameter, height: model.diameter)
                        .glassEffect(hot ? .regular.tint(.accentColor.opacity(0.45)) : .regular,
                                     in: PetalShape(model.geometry(slot)))
                        .glassEffectID(slot.id, in: glass)
                        .glassEffectTransition(.matchedGeometry)
                        .scaleEffect(hot ? 1.05 : 1)                     // full-diameter frame, so the petal pops outward
                }
                HubView(model: model)
                    .glassEffect(.regular, in: .circle)
                    .glassEffectID("hub", in: glass)
            }
        }
        .animation(.snappy(duration: 0.12), value: model.highlighted)
        .animation(.spring(duration: 0.28, bounce: 0.15), value: model.mode)   // ⇧ → ⌘ morph
    }
}
```

- **Mode switching** (convert → tools → actions): slot IDs are stable per mode. The container plus `glassEffectID` morph the shared hub and fade or matched-geometry the petals. When a slot count changes, `PetalShape`'s `animatableData` interpolates the angles.
- **`.interactive()` does not help during a drag.** Interactive glass reacts to pointer hover and press in *our* window. During an external drag the mouse events go to the drag source (Finder), and we only get `NSDraggingDestination` callbacks. So highlight is model-driven (tint, scale, label weight). `.interactive()` is used only in keyboard and click mode (§4.6) (INFERRED from AppKit event routing; SPIKE S-W1 confirms).
- **Canvas vs Shape.** `Canvas` is immediate-mode. It cannot host `glassEffect`, has no per-element accessibility, and its contents can't morph by identity. Use `Shape` petals for everything glass. `Canvas` is fine for non-glass decoration (a progress ring around the hub during a long drop, tick marks) and for an optional "Solid" high-contrast theme.
- **Transparency and backdrop.** Glass in a clear, borderless panel samples the content behind the window (`NSHostingView` with `GlassEffectContainer`, `glassEffectID`, `.tint`; SPIKE S-W2). Honour `accessibilityReduceTransparency` by switching to `.identity` glass plus a solid material fill, and `accessibilityReduceMotion` by replacing springs with 80 ms opacity fades.
- **120 Hz.** SwiftUI animations on macOS are driven by the window's display, so ProMotion panels animate at up to 120 Hz automatically (INFERRED; verify with the Instruments "Hitches" template, S-W2). Budget: ≤12 petals plus a hub inside one container. Avoid `GeometryReader` and per-frame model churn, and update `highlighted` only when the slot actually changes. Our own animation drivers (if any) use `NSView.displayLink(target:selector:)` with `preferredFrameRateRange = .init(minimum: 80, maximum: 120, preferred: 120)`.

### 2.4 Haptics and sound

- **Haptics:**
  - On a slot change, call `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`. We prefer `.now` over `.drawCompleted` because the highlight is already one frame behind.
  - Mode switch: `.levelChange`. Successful drop: `.generic`.
  - Haptics fire only on Force Touch trackpads with a finger in contact, which is true during a trackpad drag. Magic Mouse has none.
- **Sound:** a 20–40 ms original tick, loaded once with `AudioServicesCreateSystemSoundID` and played with `AudioServicesPlaySystemSound`. That gives low latency, overlapping playback, no `NSSound` pool and nothing on the main thread. Volume follows the system alert volume.
- Both sit behind one "Sounds & haptics" setting. We default haptics **on** and sound **on but quiet**, and play no sound when the system's "Play user interface sound effects" is off (read on launch; SPIKE S-W4 for the key).

---

## 3. App shell: menu bar, Settings, onboarding, login item, updates, CI

### 3.1 App lifecycle and menu bar

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| SwiftUI `App` + `MenuBarExtra(.menu)` + `Settings` scene | Least code | No programmatic open/close of the extra, and no access to the status item's button frame (needed to point onboarding at it). Opening the `Settings` scene from non-SwiftUI code in an agent app needs `openSettings` from a SwiftUI context, and the old `showSettingsWindow:` selector is blocked (workarounds like the SettingsAccess package exist). Activation quirks in `LSUIElement` apps | No |
| SwiftUI `App` + `MenuBarExtra(.window)` | Rich popover for live tasks | Same limits, plus a custom window that isn't a real menu (keyboard navigation and accessibility are weaker) | No |
| **AppKit `NSApplication` + `NSStatusItem` + `NSMenu`; SwiftUI views hosted in AppKit windows** | Full control: `menuNeedsUpdate` rebuilds, an `NSMenuItem.view` hosting a SwiftUI progress row per active task, the button frame for onboarding, a right-click alternate menu. We need AppKit for the panels anyway | Slightly more glue | **Yes** |

```swift
@main @MainActor enum ZivletMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()          // composition root: TriggerController, WheelController, JobScheduler, StatusMenu …
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // and LSUIElement = YES in Info.plist
        app.run()
    }
}
```

- Status menu: state line ("Ready" / "Working on N"), active tasks (one SwiftUI row each with a progress bar and cancel), Recent results (reveal / undo), Settings… (⌘,), Getting Started…, Check for Updates…, About, Quit.
- On macOS 26 the user can hide menu bar items. `applicationShouldHandleReopen(_:hasVisibleWindows:)` (double-clicking the app) therefore opens Settings, so the app is never unreachable.
- Use `ProcessInfo.processInfo.disableAutomaticTermination("Watching drag gestures")`. Wrap jobs in `beginActivity(options: [.userInitiated, .idleSystemSleepDisabled])`.
- Windows are opened after `NSApp.activate()` (cooperative activation, macOS 14+). `activateIgnoringOtherApps` is deprecated.

### 3.2 Settings

- An `NSWindowController` with `NSTabViewController(tabStyle: .toolbar)`. Each pane is an `NSHostingController` wrapping a SwiftUI `Form { … }.formStyle(.grouped)`. That gives native preferences-toolbar behaviour with no `Settings`-scene activation problems.
- Panes: **General** (wheel keys recorder with live preview, sounds and haptics, launch at login, ignore list), **Formats** (defaults per target: quality, keep metadata, naming), **Tools**, **Keyboard & Automation** (global hotkey, Services, CLI install, "Use Finder selection" opt-in, Esc opt-in), **Updates** (bound to Sparkle's `SPUUpdater.automaticallyChecksForUpdates` / `automaticallyDownloadsUpdates`), **Advanced** (helper versions and licences, diagnostics export, concurrency width override).
- Storage: `UserDefaults` behind a typed `@Observable SettingsStore` with versioned migrations. Never use `@AppStorage` scattered through views.

### 3.3 Onboarding

The window is 720×480, hosting SwiftUI pages. There is **no folder-grant page and no paywall**.

1. **Welcome.**
2. **Practice drag.** A sample file sits in the onboarding window. The user drags it, taps ⇧, and the *real* trigger and wheel open over the onboarding window (live key caps from the bindings). It is the same code path, so this doubles as a self-test: if the wheel doesn't appear, show diagnostics.
3. **Tools and actions practice** with ⌘ and ⌃.
4. **Keyboard path.** Explain the Services shortcut and offer to set the global hotkey.
5. **Privacy expectations.** Explain the one-time macOS prompts that **unsandboxed** apps still get when writing beside files in protected locations. TCC guards Desktop, Documents, Downloads, iCloud Drive, removable and network volumes even for unsandboxed apps. A dropped file is user-intent access to *that file*, but creating a sibling in `~/Desktop` triggers "Zivlet would like to access files in your Desktop folder" (INFERRED from TCC behaviour; **SPIKE S-P1** confirms per location). Optional "Grant now" buttons touch each folder so the prompts appear here instead of mid-conversion.
6. **Launch at login + updates.** Toggles that default on, with Sparkle checking, so Sparkle's own second-launch permission prompt never appears (set `SUEnableAutomaticChecks` from this choice).
7. **Move to Applications.** If `Bundle.main.bundleURL` is under `/Volumes/` or translocated, offer to move. `SMAppService` and Sparkle both need a stable, writable location.

`didCompleteOnboarding` is written only at the end. Quitting midway resumes on next launch, so onboarding is never silently skipped.

### 3.4 Launch at login

```swift
import ServiceManagement
@MainActor func setLaunchAtLogin(_ on: Bool) throws {
    on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
}
// SMAppService.mainApp.status: .enabled / .requiresApproval / .notRegistered / .notFound
// .requiresApproval → SMAppService.openSystemSettingsLoginItems()
```

No helper login item is needed (macOS 13+ API). Re-read the status on `NSApplication.didBecomeActiveNotification`, because the user can toggle it in System Settings.

### 3.5 Sparkle 2 updates

- **Version:** Sparkle **2.10.0** (released 2026-09-13, OBSERVED GitHub release). It requires macOS 12+, ships as SPM (`Sparkle-for-Swift-Package-Manager.zip`, 10.2 MB), drops CocoaPods, and has delta updates and EdDSA. Unsandboxed apps need **no** installer XPC services (`SUEnableInstallerLauncherService` is sandbox-only).
- **Setup:**
  - `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` owned by `AppDelegate`.
  - The menu item targets `checkForUpdates(_:)`.
  - Info.plist:

    | Key | Value |
    |---|---|
    | `SUFeedURL` | `https://<org>.github.io/zivlet/appcast.xml` |
    | `SUPublicEDKey` | base64 key from `generate_keys` |
    | `SUVerifyUpdateBeforeExtraction` | YES |
    | `SURequireSignedFeed` | YES (sign the appcast with `sign_update`) |
    | `SUEnableSystemProfiling` | NO (no telemetry) |

- **Keys:** run `./bin/generate_keys` once on the maintainer's Mac. Export with `generate_keys -x private.key`, store it as the GitHub secret `SPARKLE_ED_PRIVATE_KEY`, and keep an offline backup. Losing the key strands every installed user.
- **Appcast generation in CI:** `echo "$SPARKLE_ED_PRIVATE_KEY" | ./bin/generate_appcast --ed-key-file - --download-url-prefix "https://github.com/<org>/zivlet/releases/download/v$VER/" --maximum-deltas 3 --embed-release-notes -o site/appcast.xml updates/`. Flags verified in Sparkle's `generate_appcast/main.swift` (OBSERVED; `--ed-key-file -` reads the key from stdin, `-s` is deprecated). `updates/` holds the previous 3 DMGs (cached artifact) plus the new one, so deltas are generated. Upload the DMG **and the `.delta` files** to the release, and commit `appcast.xml` to `gh-pages`. Existing items are preserved from the current feed, so older URLs with their own version prefix stay valid.
- **Why GitHub Pages and not `releases/latest/download/appcast.xml`:** a stable URL, the full history in one feed, beta channels (`--channel beta`) and phased rollout (`--phased-rollout-interval`) all work.
- **Archive:** one artifact, `Zivlet-<ver>.dmg` (APFS, lzfse; signed, notarized, stapled). It serves both the website download and the Sparkle enclosure.
- Homebrew cask: `livecheck { url :url; strategy :sparkle }` plus `binary "#{appdir}/Zivlet.app/Contents/Helpers/zivlet"` (§4.4).

### 3.6 Signing, hardened runtime, notarization CI

**Bundle layout** (helper binaries from the engine docs):

```
Zivlet.app/Contents/
  MacOS/Zivlet
  Helpers/            ffmpeg, ffprobe, cwebp, zivlet (CLI), …   ← Mach-O executables, signed individually
  Frameworks/         Sparkle.framework (Autoupdate, Updater.app, XPCServices inside)
  PlugIns/            ZivletFinderSync.appex (P1)
  XPCServices/        ZivletWorker.xpc (§5.4, by 1.0)
  Resources/          jre/ (if the Java route survives), js/, exiftool/ (perl scripts as resources)
```

**Rules:**
- Sign **inside-out**: helpers → nested runtimes (every dylib and executable under `jre/`) → frameworks and XPC → appex → the app.
- Never use `codesign --deep` to *sign* (Apple discourages it). Using it to *verify* is fine.
- Every Mach-O gets `--options runtime --timestamp`.
- Non-Mach-O scripts belong in `Resources/`, not `MacOS/` or `Helpers/`.

**Entitlements (hardened runtime):**

| Target | Entitlements |
|---|---|
| App | `com.apple.security.automation.apple-events` = true, only to enable the opt-in Finder-selection feature (plus `NSAppleEventsUsageDescription` in Info.plist). Nothing else: no `disable-library-validation`, no JIT. |
| ffmpeg/ffprobe/cwebp/CLI | none |
| Java runtime binaries (if kept) | `com.apple.security.cs.allow-jit`, plus `com.apple.security.cs.allow-unsigned-executable-memory` if JDK 21 needs it (SPIKE S-C2) |
| Finder Sync appex | `com.apple.security.app-sandbox` (extensions must be sandboxed), app group for IPC |

**Where helpers are signed:** a Run Script build phase after "Copy Helpers" signs them with `$EXPANDED_CODE_SIGN_IDENTITY` and `Config/Helper.entitlements`. `xcodebuild archive` + `-exportArchive` (method `developer-id`, manual signing) then signs Sparkle, the appex and the app correctly. Sparkle's docs recommend this export path for its nested tools (OBSERVED).

**GitHub Actions** (`.github/workflows/release.yml`, on tag `v*`). Runner `macos-26` is arm64 and GA since 2026-02-26 (OBSERVED GitHub changelog), with Xcode 26.6 as default (Xcode 27 is in preview on images):

```yaml
jobs:
  release:
    runs-on: macos-26
    environment: release            # secrets only on the main repo; forks never sign
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - run: sudo xcode-select -s /Applications/Xcode_26.6.app
      - uses: actions/cache@v4      # prebuilt helpers keyed by Vendor/versions.lock hash
        with: { path: Vendor/build, key: helpers-${{ hashFiles('Vendor/versions.lock') }} }
      - run: Scripts/build-helpers.sh            # only on cache miss; verifies SHA-256 of sources
      - name: Import Developer ID cert
        env: { P12: ${{ secrets.DEVID_P12_BASE64 }}, P12_PW: ${{ secrets.DEVID_P12_PASSWORD }} }
        run: |
          security create-keychain -p ci build.keychain
          security default-keychain -s build.keychain && security unlock-keychain -p ci build.keychain
          echo "$P12" | base64 -d > cert.p12
          security import cert.p12 -k build.keychain -P "$P12_PW" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k ci build.keychain
      - run: xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Release
               -archivePath build/Zivlet.xcarchive ARCHS=arm64 archive
      - run: xcodebuild -exportArchive -archivePath build/Zivlet.xcarchive
               -exportOptionsPlist Config/ExportOptions.plist -exportPath build/export
      - run: Scripts/verify-signatures.sh build/export/Zivlet.app   # codesign --verify --strict --deep; checks runtime flag on every Mach-O
      - name: Notarize app, staple, build DMG, notarize DMG
        env: { ASC_KEY: ${{ secrets.ASC_KEY_P8_BASE64 }}, ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}, ASC_ISSUER: ${{ secrets.ASC_ISSUER_ID }} }
        run: |
          echo "$ASC_KEY" | base64 -d > AuthKey.p8
          ditto -c -k --keepParent build/export/Zivlet.app build/Zivlet.zip
          xcrun notarytool submit build/Zivlet.zip --key AuthKey.p8 --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait --timeout 45m
          xcrun stapler staple build/export/Zivlet.app
          Scripts/make-dmg.sh build/export/Zivlet.app "build/Zivlet-${GITHUB_REF_NAME#v}.dmg"   # hdiutil APFS + codesign the DMG
          xcrun notarytool submit build/Zivlet-*.dmg --key AuthKey.p8 --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait
          xcrun stapler staple build/Zivlet-*.dmg
          spctl -a -vvv -t install build/Zivlet-*.dmg
      - run: Scripts/appcast.sh      # generate_appcast as in §3.5, gh release upload, push gh-pages
        env: { SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}, GH_TOKEN: ${{ github.token }} }
```

Also add a `ci.yml` for PRs: build plus tests, unsigned (`CODE_SIGNING_ALLOWED=NO`), with the golden-test subset. Ship **arm64-only** for 1.0. macOS 26 still runs on a few late Intel Macs, but universal helpers would roughly double ffmpeg and related sizes. Revisit if users ask.

---

## 4. Extensibility (differentiators)

App Intents, a URL scheme, Services and extensions give Zivlet an automation surface that drag-wheel utilities typically lack. Every item below is a Zivlet differentiator.

### 4.1 App Intents (Shortcuts, Spotlight, Siri)

```swift
struct ConvertFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert Files"
    static let description = IntentDescription("Convert files to another format, locally.")
    static let openAppWhenRun = false
    @Parameter(title: "Files", supportedContentTypes: [.item]) var files: [IntentFile]
    @Parameter(title: "Format") var format: OutputFormat          // AppEnum generated from the registry
    @Parameter(title: "Save Beside Originals", default: true) var besideOriginals: Bool
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let outputs = try await Zivlet.shared.scheduler.convert(files.map(\.source), to: format,
                                                                 placement: besideOriginals ? .beside : .temporary)
        return .result(value: outputs.map { IntentFile(fileURL: $0) })
    }
}
```

- **Intents:** Convert Files, Compress (target size), Strip Metadata, Run Tool (enum), Read QR (returns `String`), Extract Text (OCR), Images → PDF, Merge PDFs, Get Supported Formats.
- Return files so actions chain. An `AppShortcutsProvider` adds Siri and Spotlight phrases. On macOS 26, Spotlight can run App Intents actions directly (INFERRED; verify with S-X2).
- **Placement:** intent types live **in the app target** (thin wrappers over `ZivletRuntime`). Developer reports show metadata-extraction and localization problems for intents and AppEnums defined only inside SPM packages, and `AppIntentsPackage` is needed only for cross-package entity conformances (OBSERVED forum threads). Thin wrappers avoid all of that.
- **Free compound features:**
  - Shortcuts "Quick Action" shortcuts appear in Finder's Quick Actions menu.
  - Shortcuts automations on the Mac (macOS 26) can call our intents from folder triggers, which gives "watch folder" without us building it (INFERRED; verify the trigger list, S-X2).
  - The Shortcuts "Use Model" action composes Apple Intelligence with our intents.

### 4.2 Services menu: the zero-permission keyboard path

```xml
<key>NSServices</key>
<array><dict>
  <key>NSMenuItem</key>      <dict><key>default</key><string>Open in Zivlet</string></dict>
  <key>NSMessage</key>       <string>openWheel</string>
  <key>NSPortName</key>      <string>Zivlet</string>
  <key>NSSendFileTypes</key> <array><string>public.item</string></array>
  <key>NSRequiredContext</key><dict/>
</dict></array>
```

`NSApp.servicesProvider = ServicesProvider()` with `@objc func openWheel(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>)`. Call `NSUpdateDynamicServices()` on first launch. The user assigns any shortcut in System Settings › Keyboard › Keyboard Shortcuts › Services › Files and Folders (onboarding deep-links there).

The service receives the Finder selection on a pasteboard and needs no Apple Events or Accessibility. It then opens the wheel in **keyboard mode** at the mouse (§4.6). This is the default answer to "Enter on a file". Do not ship a default `NSKeyEquivalent`, because collisions are common.

### 4.3 Finder Sync extension and Quick Actions

- **Finder Sync (P1):** a context submenu "Zivlet ▸ Convert to ▸ JPEG / PNG / …, Tools ▸ …" plus an optional toolbar button.
  - Set `directoryURLs = [URL(fileURLWithPath: "/")]`.
  - `FIFinderSyncController.default().selectedItemURLs()` is valid **only inside `menu(for:)` and its actions** (OBSERVED Apple docs), so it is not a general "get selection" API.
  - The extension is sandboxed. It forwards URLs to the app over an app-group Mach service or `NSWorkspace.open(zivlet://…)`. The app writes outputs (unsandboxed, no grant needed).
  - The user must enable it in System Settings › General › Login Items & Extensions. Onboarding links there.
- **Quick Actions:** no custom code needed beyond App Intents. We ship two importable `.shortcut` files ("Convert with Zivlet", "Compress with Zivlet") marked "Use as Quick Action". An Action extension is possible later if the Finder preview-pane button matters.

### 4.4 `zivlet` CLI

- An executable target in `ZivletKit` linking `ZivletCore`, `ZivletEngines` and `ZivletRuntime`, plus `swift-argument-parser` **1.7.2**.
- It runs engines **in-process, headless**, and does not need the app running. It finds helpers by resolving its own realpath, then `../Helpers/`.

```
zivlet convert IMG_0001.heic *.png --to webp --quality 80 [--out-dir DIR] [--json]
zivlet tool compress clip.mov --target-size 10MB
zivlet tool strip-metadata *.jpg
zivlet formats [--from heic] [--json]          # registry dump, also feeds docs and tests
zivlet info file.mp4 --json
zivlet wheel file1 file2                        # hands off to the app: opens the wheel in keyboard mode
```

- Exit codes: `0` ok, `1` some items failed, `2` usage, `3` unsupported pair, `130` cancelled (SIGINT forwarded to children through the scheduler's teardown).
- Install:
  - Homebrew cask `binary` stanza (preferred).
  - Or Settings › "Install command-line tool", which symlinks to `/usr/local/bin` via `NSAppleScript("do shell script \"ln -sf …\" with administrator privileges")`, or to `~/.local/bin` without admin.
- The CLI is the base for the Raycast extension and an MCP server later (P2).

### 4.5 URL scheme `zivlet://`

`zivlet://wheel?path=…&path=…`, `zivlet://settings/keyboard`, `zivlet://onboarding`.

**Security rule:** any web page can invoke a URL scheme (the browser only confirms "Open Zivlet?"). URL actions therefore only **open UI with files preselected**. They never run a tool or write files without an in-app confirmation. Automation goes through the CLI or App Intents instead.

### 4.6 Keyboard-only flow

1. **Trigger options:**
   - (a) Services shortcut (zero permission, default).
   - (b) Global hotkey via `sindresorhus/KeyboardShortcuts` (MIT, 3.1.0; Carbon hotkeys, no permission). Default unset, suggestion ⌃⌥⌘S. Never bind bare Enter: Finder uses it for rename, and a Carbon hotkey would swallow it.
2. **Getting the selection for (b):**
   - If Finder is frontmost and the user enabled "Use Finder selection", send an Apple Event:

     ```swift
     let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
     let st = AEDeterminePermissionToAutomateTarget(finder.aeDesc, typeWildCard, typeWildCard, false)
     // noErr = granted; -1744 errAEEventWouldRequireUserConsent = not asked yet; -1743 = denied; -600 = Finder not running
     ```

     Ask only when the user flips the toggle (`askUserIfNeeded: true`), never by surprise. Then run, on the main actor via `NSAppleScript`:

     ```applescript
     tell application "Finder"
       set out to {}
       repeat with i in (get selection)
         set end of out to POSIX path of (i as alias)
       end repeat
       return out
     end tell
     ```

     ScriptingBridge is no better: it needs the same Automation consent and adds generated headers.
   - Without consent, the hotkey falls back to the Services path or a quick "Choose files…" panel.
   - Synthesising ⌘C needs post-event (Accessibility) permission and clobbers the clipboard. Rejected.
3. **Wheel in keyboard mode:**
   - `panel.keyboardMode = true; panel.makeKey()` makes the nonactivating panel key without activating the app, so Finder stays frontmost.
   - Keys: arrows / Tab rotate the highlight; 1–9 pick slots; type-to-filter (e.g. "we" → WebP); ⌘ / ⌃ switch wheels; Enter applies; Esc closes. All are local events, no permission.
   - Petals become `Button`s with accessibility labels, so VoiceOver can operate the wheel (impossible mid-drag).

### 4.7 Apple Intelligence (optional, P2)

- **Foundation Models** (macOS 26, on-device): a "Describe what you want" field in keyboard mode. For example, "under 8 MB for Discord" becomes a `@Generable struct Plan { operation: Operation; format: OutputFormat?; targetBytes: Int? }`, constrained by guided generation to registry enums, then shown as a confirmable preset.
- Gate on `SystemLanguageModel.default.availability == .available`. Never required, never networked.
- Zero-code leverage: our App Intents plus the Shortcuts "Use Model" action.
- Vision (OCR, faces, QR) is not "Apple Intelligence" and is covered in the engine docs.

---

## 5. Project structure, testing, concurrency

### 5.1 Build system

| Option | Notes | Verdict |
|---|---|---|
| **Plain Xcode project + local SPM package** | Xcode 16+ *synchronized folders* mean adding files no longer edits `project.pbxproj`, so merge conflicts mostly disappear. Extension targets, entitlements, signing, Copy Files and Run Script phases are first-class. Contributors just open it | **Yes** |
| XcodeGen 2.46.0 (2026-07-16) | A readable `project.yml` and a generated project; still maintained. Adds `brew install xcodegen` for every contributor and CI | Fallback if pbxproj conflicts become painful |
| Tuist 4 | Powerful (caching, graph), but a heavier toolchain dependency and conventions, aimed at large teams | No |

```
Zivlet/
  Zivlet.xcodeproj           # targets: Zivlet (app), ZivletFinderSync (appex, P1), ZivletWorker (xpc), zivlet (CLI, from the package product)
  App/                        # synchronized folder: AppDelegate, Intents/, Info.plist, Zivlet.entitlements, Assets.xcassets
  Extensions/FinderSync/
  Config/                     # Base.xcconfig, Debug/Release.xcconfig, *.entitlements, ExportOptions.plist
  Packages/ZivletKit/
    Package.swift
    Sources/
      ZivletCore/            # Format/UTI registry, 275-pair matrix, tool specs, naming, Job/Result models (Foundation only)
      ZivletEngines/         # Engine protocol + ImageIO/AVFoundation/PDFKit/ffmpeg/cwebp/archive/document engines
      ZivletRuntime/         # JobScheduler actor, lanes, staging + atomic publish, undo log, progress streams
      ZivletTrigger/         # TriggerMachine (pure) + AppKit sampler
      ZivletWheel/           # WheelPanel, WheelDropView, WheelModel, PetalShape, glass views, haptics/sound
      ZivletUI/              # Settings panes, onboarding, tool editors, Float shelf, progress/result card
      zivlet-cli/            # ArgumentParser executable
    Tests/                    # ZivletCoreTests, ZivletEnginesTests (golden), ZivletRuntimeTests, ZivletTriggerTests, ZivletWheelTests
  Vendor/                     # versions.lock, build scripts for ffmpeg/libvpx/opus/…, licences
  Fixtures/                   # generator script + small committed fixtures (Git LFS for the larger corpus)
  Scripts/  .github/workflows/
```

```swift
// swift-tools-version: 6.2
import PackageDescription
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),   // SE-0461
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
]
let ui = strict + [.defaultIsolation(MainActor.self)]           // SE-0466
let package = Package(
    name: "ZivletKit", platforms: [.macOS(.v26)],
    products: [.library(name: "ZivletKit", targets: ["ZivletUI", "ZivletWheel", "ZivletTrigger", "ZivletRuntime"]),
               .executable(name: "zivlet", targets: ["zivlet-cli"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(name: "ZivletCore", swiftSettings: strict),
        .target(name: "ZivletEngines", dependencies: ["ZivletCore", .product(name: "Subprocess", package: "swift-subprocess")], swiftSettings: strict),
        .target(name: "ZivletRuntime", dependencies: ["ZivletEngines"], swiftSettings: strict),
        .target(name: "ZivletTrigger", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletWheel", dependencies: ["ZivletTrigger", "ZivletCore"], swiftSettings: ui),
        .target(name: "ZivletUI", dependencies: ["ZivletWheel", "ZivletRuntime", "KeyboardShortcuts"], swiftSettings: ui),
        .executableTarget(name: "zivlet-cli", dependencies: ["ZivletRuntime", .product(name: "ArgumentParser", package: "swift-argument-parser")], swiftSettings: strict),
        // test targets …
    ]
)
```

Sparkle is added to the **app target** only, so the CLI and the package stay Sparkle-free.

### 5.2 Concurrency model for the job queue

- **Isolation map:**
  - UI, trigger sampler and wheel: `@MainActor`.
  - `JobScheduler`: an `actor`.
  - Engines: nonisolated `Sendable` structs whose CPU-heavy functions are `@concurrent` (Swift 6.2), so they never run on the caller's actor.
  - WebKit-based renderers (DOCX/EPUB → PDF via `WKWebView`) are `@MainActor` and sit in their own width-1 lane.
- **Lanes:**

  | Lane | Width | Covers |
  |---|---|---|
  | `.cpu` | P-core count (`sysctlbyname("hw.perflevel0.physicalcpu")`) | ImageIO, PDFKit, archives |
  | `.ffmpegSoftware` | `max(1, pCores / 4)` | each ffmpeg already uses N threads |
  | `.mediaEngine` | 2 | VideoToolbox encodes; base M-series chips have one encode engine, Max/Ultra more |
  | `.webkit` | 1 | WebKit renderers |
  | `.jvm` | 1 | memory-heavy |

  A `DispatchSource.makeMemoryPressureSource` halves widths on `.warning`.
- **Limiter:** a small cancellation-aware async semaphore (~40 lines, actor-based). `groue/Semaphore` (MIT) is a reference, but its last release was 0.1.0 in 2024, so write and test our own.
- **Batch fan-out with bounded width:**

```swift
func run(_ batch: [Job], width: Int) async -> [JobResult] {
    await withTaskGroup(of: JobResult.self) { group in
        var pending = batch.makeIterator(), results: [JobResult] = []
        for _ in 0..<width { if let j = pending.next() { group.addTask { await self.execute(j) } } }
        for await r in group {
            results.append(r); events.yield(.finished(r))
            if let j = pending.next() { group.addTask { await self.execute(j) } }
        }
        return results
    }
}
```

- **Process spawning and cancellation** with `swift-subprocess` 1.0.2 (Apache-2.0, macOS 13+, source-stable since 1.0.0 on 2026-08-04; OBSERVED):

```swift
var opts = PlatformOptions()
opts.teardownSequence = [.send(signal: .interrupt, allowedDurationToNextStep: .milliseconds(800)),
                         .gracefulShutDown(allowedDurationToNextStep: .seconds(2))]   // then SIGKILL
opts.processGroupID = 0                                                           // own group → kill children too
let result = try await run(.path(ffmpegURL.filePath), arguments: args, platformOptions: opts,
                           output: .sequence, error: .string(limit: 64 * 1024)) { execution in
    for try await line in execution.standardOutput.lines() { progress.ingest(line) }   // -progress pipe:1 -nostats
}
```

  - Cancelling the job's `Task` triggers the teardown. Target: kill within 500 ms (Zivlet spec).
  - Set QoS with `preSpawnProcessConfigurator` → `posix_spawnattr_set_qos_class_np(&attr, QOS_CLASS_USER_INITIATED)` for interactive drops and `QOS_CLASS_UTILITY` for batches.
- **Staging and publication:**
  - Each job writes into `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: source, create: true)` (same volume).
  - It validates the output (opens, probes) and publishes with `renamex_np(tmp, dest, RENAME_EXCL)` in a collision loop (`name 2.ext`, …). Readers therefore never see partial files, and existing files are never overwritten.
  - The undo log records the published paths.
- **Quit:** `applicationShouldTerminate` returns `.terminateLater`, cancels all jobs, waits ≤2 s, then replies.
- **Crash isolation:** external tools are already separate processes. By 1.0, move in-process Apple-framework engines (ImageIO, PDFKit, AVFoundation readers) into **`ZivletWorker.xpc`**: unsandboxed, same team, Swift `XPCSession`/`XPCListener` (macOS 14+) with `Codable` requests. A malformed file then can't take down the trigger and the menu bar app, and launchd reclaims the worker's memory when idle. WebKit renderers stay in the app. Design `Engine` requests as `Codable` from day one so the move is mechanical.

### 5.3 Testing strategy

| Layer | Framework | What |
|---|---|---|
| Core (registry, naming, matrix) | Swift Testing (`import Testing`) | `@Test(arguments: Registry.allPairs)`: every one of the 275 pairs resolves to an engine and an output name. Collision naming, `.tar.gz` double extensions, Unicode and case-insensitive collisions |
| Trigger | Swift Testing | `TriggerMachine` fed **recorded JSON traces** (captured with a debug "record trigger trace" menu) for Finder, Mail, Safari, a ⌘-held move drag, double taps, mode switches and cancel-by-retap. Pure, fast, deterministic |
| Engines (golden) | Swift Testing, `.tags(.golden)`, `.timeLimit(.minutes(2))` | Fixtures are **generated** deterministically by `Fixtures/generate.sh` (ffmpeg `lavfi` `testsrc2`/`sine`, scripted DOCX/XLSX, rendered PDFs), plus a small real-world corpus in Git LFS. **Compare properties, not bytes** (encoders change between versions): image dimensions, colour space, alpha, PSNR/SSIM ≥ threshold against the reference via vImage; audio codec, sample rate, channels, duration ±20 ms, RMS; video codec, profile, dimensions, duration ±1 frame, and **WebM = VP9/AV1 + Opus actually playable** (a known failure mode); PDF page count, extracted text, rendered-page perceptual hash; documents normalized text. On failure, attach the diff images with Swift Testing attachments |
| Runtime | Swift Testing | Lane width honoured, cancellation kills the process group within 500 ms (spawn `sleep` / `yes`), staging never leaves partial files, memory-pressure downgrade. Exit tests for crash paths |
| Wheel geometry | Swift Testing + snapshot of the non-glass "Solid" theme (`ImageRenderer` can't reproduce window-backdrop glass) | Petal angles, gaps, edge-of-screen layouts, label fitting |
| Windows (Settings, onboarding, tool editors, keyboard-mode wheel) | XCUITest | Launch argument `-UITestFixture <dir>` opens the wheel in keyboard mode with fixture files, so no real cross-app drag is needed |
| Real drags | Manual QA matrix per release, plus an optional self-hosted runner with a CGEvent-posting harness (needs Accessibility on that machine only) | Finder, Desktop, Mail, Safari, Chrome, Photos, VS Code, Dropover running, full-screen Space, 2 displays with mixed refresh rates, Stage Manager |
| Performance | `XCTOSSignpostMetric` / `OSSignposter` | Modifier sample → first wheel frame p95 ≤16 ms (M1 Air). HEIC 12 MP → JPEG ≤150 ms (Zivlet spec) |

Coverage gate: 80 % on `ZivletCore`, `ZivletRuntime`, `ZivletTrigger` and `ZivletEngines`. UI is excluded.

---

## 6. Diagnostics without telemetry

- `Logger(subsystem: "app.zivlet", category: …)` with `privacy: .private` for paths.
- A "Copy diagnostics" button in Settings › Advanced. It collects helper versions, the last 200 log lines (`OSLogStore(scope: .currentProcessIdentifier)`), the trigger trace and settings.
- MetricKit (`MXMetricManager`) payloads are kept **locally** for the user to attach to a GitHub issue. Nothing is sent.

## 7. Superseded items from the earlier sandboxed-app plan

- Folder grants, security-scoped bookmarks and the "URL peek cancels the drop grant" pitfall: **gone** (unsandboxed). They are replaced by the TCC protected-folder prompts (§3.3, S-P1).
- StoreKit, the trial counter and the MAS LGPL concerns: gone (free, GPL, direct download).
- macOS 13 fallbacks (layer-drawn petals): gone. The Liquid Glass and Solid themes only.

## 8. Risk register

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | Apple filters global mouse monitors or drag-pasteboard `changeCount` behind TCC in a future macOS (as it did with `CGEventSourceKeyState` for keys) | Low / High | The trigger is isolated behind `InputSampler`. Fall back to an opt-in Input Monitoring tap. Watch each macOS beta (S-T1 rerun per beta) |
| R2 | Pasteboard privacy (alerts on programmatic reads, shipped as a developer preview in 15.4; macOS 26 status unclear) extends to the drag pasteboard | Low / Med | Only `changeCount` + `availableType` mid-drag, and URL reads only inside `performDragOperation` (user-initiated drop). Use `detect…` APIs if needed |
| R3 | Latency target missed on 60 Hz external displays | Med / Low | Event-driven `flagsChanged` if S-T2 passes. Otherwise accept ≤2 frames at 60 Hz (≤33 ms) on externals and document it |
| R4 | Glass rendering cost or bugs in a transparent panel (morphing glitches, GPU spikes on 8 GB Macs) | Med / Med | One `GlassEffectContainer`, ≤12 petals, pre-warm. A "Solid" theme as a user toggle and automatic fallback when Reduce Transparency is on |
| R5 | TCC prompts mid-conversion confuse users ("why does a converter want my Desktop?") | High / Med | Onboarding pre-explains and pre-triggers. Copy in the progress card. Never request Full Disk Access |
| R6 | Sparkle EdDSA key loss or leak | Low / Critical | Offline backup, a GitHub `environment` secret with required reviewers, signed feeds |
| R7 | Notarization rejects nested binaries (missing runtime flag, unsigned dylibs in the JRE, scripts in `MacOS/`) | Med / Med | `verify-signatures.sh` checks every Mach-O for `flags=0x10000(runtime)` and a timestamp before submitting. Fetch `notarytool log` on failure |
| R8 | Finder Sync extension enablement friction, or Apple moving its settings again (it did in macOS 15) | Med / Low | It is P1 and optional. Services and App Intents are the primary paths |
| R9 | App Intents metadata issues with package-defined types | Med / Low | Intents live in the app target |
| R10 | Unsandboxed app plus untrusted media parsers mean that a parser exploit has user privileges | Low / High | Keep helpers updated (`versions.lock` with automated bump PRs), worker XPC by 1.0, later a sandboxed worker with FD passing |
| R11 | `/usr/bin/perl` (ExifTool route) removed in a future macOS | Low / Med | Engine docs decide. The platform supports bundling a relocatable perl in `Resources/` |

## 9. Spikes (do before feature work; each ≤1 day)

| ID | Question | Pass criterion |
|---|---|---|
| S-T1 | Do global mouse monitors fire during Finder, Mail, Safari and Chrome drags on macOS 26.x and 27, unprompted, for a Developer-ID-signed agent app? | Events seen for all four sources. No TCC entry is created |
| S-T2 | Are `flagsChanged` events delivered without permission through (a) an `NSEvent` global monitor and (b) a listen-only `CGEventTap` (created without a prompt per the probe)? | Edges arrive with <2 ms delay, with `CGPreflightListenEventAccess() == false` |
| S-T3 | Does a Carbon hotkey for unmodified Esc register in an unsandboxed app, and fire while Finder owns a drag? Does the drag continue? | Wheel closes, drag continues |
| S-T4 | End-to-end latency, from the signpost at the modifier sample to the first wheel frame, on an M1 Air and a 120 Hz MBP | p95 ≤16 ms (120 Hz), ≤33 ms (60 Hz) |
| S-T5 | File-promise drags from Mail, Photos, Safari, Chrome, Arc and Firefox: are types present mid-drag, and does `receivePromisedFiles` succeed at drop? | Each source either works or is explicitly listed as unsupported |
| S-W1 | Confirm `.interactive()` glass gets no hover during an external drag. Is the model-driven highlight smooth at 120 Hz? | Instruments shows no hitches over 2 frames |
| S-W2 | Glass morph between 6 and 12 petals in a transparent `.popUpMenu` panel over a full-screen video app | Correct backdrop sampling, GPU <10 % on M1 |
| S-W3 | Edge-of-screen layout: compact or rotate vs clamp | Usability check with 3 people |
| S-W4 | Reading "Play user interface sound effects" | Reliable key, or drop the feature |
| S-P1 | Which locations prompt (Desktop, Documents, Downloads, iCloud Drive, external, SMB) when writing a sibling of a dropped file, from the app and from a spawned `ffmpeg` | Documented table and onboarding copy |
| S-C1 | Full CI dry run: archive, sign helpers, export, notarize, staple, DMG, appcast with a delta, Sparkle update from N-1 | Update installs and Gatekeeper passes on a clean VM |
| S-C2 | JRE signing entitlements (only if the Java route survives the engine docs) | Notarized, launches under the hardened runtime |
| S-X1 | Services entry appears for files in Finder and Desktop, and a user-assigned shortcut opens keyboard mode with the selection | Works without any TCC prompt |
| S-X2 | macOS 26 Shortcuts automation folder triggers can call `ConvertFilesIntent` | Works, or remove the claim |

---

## 10. RECOMMENDATION

**Choice**

1. **Trigger:** a hybrid, permission-free detector.
   - Global and local `NSEvent` *mouse* monitors wake the app when a drag starts (zero idle polling).
   - While a file drag is live, a display-synced sampler reads modifiers, button state and the drag pasteboard `changeCount` and types (120 Hz on ProMotion; ~0.6 % of a core, measured).
   - Optional event-driven `flagsChanged` if S-T2 confirms delivery without permission.
   - Cancel by re-tapping the same key or dropping on the hub. Esc through a visible-only Carbon hotkey (S-T3), or an opt-in Input Monitoring tap.
   - Never require Accessibility or Input Monitoring.
2. **Overlay:**
   - A pre-warmed borderless `.nonactivatingPanel` at `.popUpMenu` with `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .stationary, .ignoresCycle]`.
   - An AppKit `NSDraggingDestination` view doing polar hit-testing.
   - A SwiftUI wheel: `GlassEffectContainer`, custom animatable `Shape` petals with `glassEffect(.regular.tint(...))`, and `glassEffectID` + `.matchedGeometry` for morphing between modes.
   - Model-driven highlight. `.interactive()` only in keyboard mode, Canvas only for decoration.
   - `.alignment` haptics on slot change, and a sound played through AudioServices.
3. **Shell:**
   - AppKit lifecycle with `NSStatusItem` + `NSMenu` (SwiftUI rows inside). AppKit-hosted SwiftUI Settings and onboarding (practice drag, TCC expectations, move to /Applications).
   - `SMAppService.mainApp`.
   - Sparkle 2.10.0 with EdDSA and a signed feed: appcast on GitHub Pages, DMG and deltas on GitHub Releases.
   - GitHub Actions on `macos-26`: inside-out hardened-runtime signing, `notarytool --wait`, stapled DMG, arm64-only.
4. **Extensibility (in order):**
   - Services menu entry (zero-permission keyboard path) and App Intents in the app target, both in 1.0.
   - `zivlet` CLI in `Contents/Helpers`, shipped through a Homebrew cask, in 1.0.
   - Opt-in Finder-selection hotkey via Apple Events and Finder Sync context menu in 1.x.
   - Foundation Models "describe it" field in P2.
   - The URL scheme only opens UI.
5. **Structure:**
   - A thin Xcode project (synchronized folders, xcconfigs) plus the local `ZivletKit` package (`Core`, `Engines`, `Runtime`, `Trigger`, `Wheel`, `UI`, CLI).
   - Swift 6 with `defaultIsolation(MainActor.self)` for UI modules.
   - `actor JobScheduler` with resource lanes and bounded `TaskGroup` fan-out; `swift-subprocess` 1.0.2 with a SIGINT → SIGTERM → SIGKILL teardown in its own process group; atomic `RENAME_EXCL` publication.
   - Engines move to an unsandboxed `ZivletWorker.xpc` before 1.0.
   - Swift Testing for unit, trace, matrix and property-based golden tests. XCUITest for windows only. A manual real-drag QA matrix.

**Rationale**

- This keeps the best property of a pure-polling design (no permission prompts) and fixes its measurable weaknesses:
  - 10 Hz polling forever: replaced by zero idle wakeups.
  - 60 Hz-quantised latency: replaced by frame-synced or event-driven detection.
  - A non-working Esc: replaced by re-tap, hub drop and the opt-in Esc paths.
  - No automation surface: replaced by Services, App Intents and the CLI.
- The macOS 26-only floor lets us use native Liquid Glass and Swift 6.2 isolation defaults with no fallback code.
- Being unsandboxed removes the whole folder-grant machinery. The only remaining file-access friction is TCC's protected-folder prompts, which onboarding handles.
- Plain Xcode plus SPM keeps the barrier low for open-source contributors, while the package boundary keeps the core testable and shared with the CLI.

**Risks**

- Apple could gate mouse monitors or the drag pasteboard behind TCC in future releases (R1, R2).
- Glass performance or bugs in transparent panels (R4).
- TCC prompts at first conversion (R5).
- Signing complexity for nested runtimes (R7).
- Sparkle key custody (R6).
- Unsandboxed parsing of untrusted files (R10).
- Several behaviours remain SPIKE-level: `flagsChanged` without permission, Esc hotkey during a drag, promise drags from browsers.

**Fallback**

- **Trigger:** if mouse monitors break, revert to pure polling (mechanism A) at 10 Hz idle and 120 Hz active. If both break, ship an opt-in Input Monitoring `CGEventTap` with clear onboarding.
- **Glass:** the "Solid" theme (Shape fills, no glass) is always available and becomes the default if S-W2 fails.
- **Menu bar:** if AppKit glue becomes a burden, `MenuBarExtra(.menu)` is a drop-in for the status menu.
- **Project:** move to XcodeGen if pbxproj conflicts appear.
- **Engines:** if the XPC worker slips, ship 1.0 with in-process engines behind the same `Engine` protocol.
- **Keyboard path:** the Services entry needs nothing from Apple Events, so it stays the guaranteed path even if Automation consent is refused.

---

## Sources

- Apple: [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer), [glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [Glass](https://developer.apple.com/documentation/swiftui/glass), [glassEffectID(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)), [glassEffectUnion(id:namespace:)](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)), [glassEffectTransition(_:)](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)), [FIFinderSyncController.selectedItemURLs()](https://developer.apple.com/documentation/findersync/fifindersynccontroller/selecteditemurls()), [NSPasteboard.AccessBehavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum)
- Sparkle: [2.10.0 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0), [documentation](https://sparkle-project.org/documentation/), [publishing](https://sparkle-project.org/documentation/publishing/), `generate_appcast/main.swift` (flags read from source via `gh api`)
- [swift-subprocess 1.0 release and README (teardownSequence, processGroupID)](https://github.com/swiftlang/swift-subprocess)
- [GitHub changelog: macOS 26 GA for hosted runners (2026-02-26)](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/), [runner-images macos-26-arm64 notes](https://newreleases.io/project/github/actions/runner-images/release/macos-26-arm64%2F20260805.0288)
- Pasteboard privacy: [Michael Tsai, "Pasteboard Privacy Preview in macOS 15.4"](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4), [Apple forums: no MDM control](https://developer.apple.com/forums/thread/794560)
- Hotkeys: [Apple forums: Sequoia RegisterEventHotKey ⌥/⇧ restriction](https://developer.apple.com/forums/thread/763878?page=2), [Shottr KB](https://shottr.cc/kb/sequoia)
- App Intents in packages: [Apple forums 759160](https://developer.apple.com/forums/thread/759160?page=2), [806804](https://developer.apple.com/forums/thread/806804), [757950](https://developer.apple.com/forums/thread/757950)
- Package versions (via `gh release list`, 2026-10-20): XcodeGen 2.46.0, KeyboardShortcuts 3.1.0 (MIT), swift-argument-parser 1.7.2, groue/Semaphore 0.1.0 (MIT, 2024)
- Local probes: `poll.swift`, `tap.swift` (local prototype, not published; macOS 27.0, Swift 6.4)
- Project research: internal platform and competitive notes (not published)

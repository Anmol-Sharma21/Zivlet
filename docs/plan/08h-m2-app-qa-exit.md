# 08h — M2 task 11: app wiring and demo · manual real-drag QA · M2 exit check

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from `$REPO`
with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 11 — AppKit app: composition root, status menu, DEBUG demo and HUD (P0-43)

| Field | Value |
|---|---|
| Goal | Replace the M1 SwiftUI `MenuBarExtra` with an AppKit accessory app (index D-M2-10). `AppDelegate` is the composition root: `DragPayloadReader` → `WheelController`; `SystemInputReader` + `SystemTriggerScheduler` + probe → `TriggerHost`; wheel effects → controller; `draggingEnded` → `.dropHandled`. Status menu: catalog counts, bindings line, Quit, and in Debug a "Show wheel (demo)" submenu per mode plus "Hide wheel". Debug launch argument `-ZivletDemoWheel <mode>` shows the wheel at screen centre without a drag. A drop logs the selection (summary `.public`, JSON `.private`) and, in Debug, shows it for 4 s in a small HUD. `make demo` automates the screenshot check |
| 05 rows | P0-43; M2 exit check |
| Sources | 14 §3.1 (AppKit lifecycle, `disableAutomaticTermination`), 05 P0-43, 01-prd NFR-6, index D-M2-3, D-M2-9, D-M2-12 |

**Files (repo root)**

| Action | Path |
|---|---|
| delete | `App/ZivletApp.swift` |
| create | `App/ZivletMain.swift`, `App/AppDelegate.swift`, `App/StatusMenu.swift`, `App/DebugHUD.swift` |
| create | `Scripts/demo-wheel.sh` (executable) |
| modify | `Makefile` (`demo` target) |

### 11.1 Failing check first

Delete the SwiftUI app and add only the new entry point, `App/ZivletMain.swift` (11.2), then build:

```bash
git rm -q App/ZivletApp.swift    # leaves App/ empty until ZivletMain.swift is written
make app 2>&1 | grep -E "error: |BUILD"
```

Expected: `error: cannot find 'AppDelegate' in scope`, and `make` exits 2.

### 11.2 Implement

`project.yml` is unchanged: the `ZivletKit` product now exports the shell modules (Task 1), and the app target
already has `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`.

`App/ZivletMain.swift`:

```swift
import AppKit

/// AppKit entry point (14 §3.1): an accessory app with a status item, no Dock icon (`LSUIElement`).
@main
enum ZivletMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
```

`App/AppDelegate.swift`:

```swift
import AppKit
import ZivletTrigger
import ZivletTriggerHost
import ZivletWheel
import ZivletWheelCore
import os

/// Composition root only (02 ADR-02, 14 §3.1): builds the trigger host, the wheel and the status menu and wires
/// them. M2 converts nothing: a drop is logged and, in Debug, shown in the dev HUD (05 P0-43).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Debug builds only: `-ZivletFlagsMonitor YES` adds the global `flagsChanged` monitor for spike P-T2 (off by
    /// default, 03a §1.8). Release never reads the default (`debugFlagsMonitorEnabled()` returns false).
    static let flagsMonitorKey = "ZivletFlagsMonitor"

    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")
    private var trigger: TriggerHost?
    private var wheel: WheelController?
    private var statusMenu: StatusMenu?
    #if DEBUG
        private let hud = DebugHUD()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let reader = DragPayloadReader()
        let wheel = WheelController(reader: reader)
        let config = TriggerConfig()
        let trigger = TriggerHost(
            config: config,
            reader: SystemInputReader(pointerInsideWheel: { [weak wheel] in wheel?.isPointerInside ?? false }),
            scheduler: SystemTriggerScheduler(),
            listensToFlagsChanged: Self.debugFlagsMonitorEnabled(),
            probe: { count in await reader.summary(changeCount: count) })
        trigger.onWheelEffect = { [weak wheel] effect in wheel?.apply(effect) }
        wheel.onDragEnded = { [weak trigger] in trigger?.receive(.dropHandled) }
        wheel.delegate = self
        statusMenu = StatusMenu(bindings: config.bindings, wheel: wheel)
        self.wheel = wheel
        self.trigger = trigger
        trigger.start()
        ProcessInfo.processInfo.disableAutomaticTermination("Watching drag gestures")
        Task {
            await wheel.prewarm()
            launchDemoIfRequested()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { trigger?.stop() }

    /// DEBUG: `-ZivletDemoWheel convert|tools|actions` shows the wheel at screen centre without a drag.
    private func launchDemoIfRequested() {
        #if DEBUG
            do {
                guard let scenario = try DemoScenario.parse(arguments: ProcessInfo.processInfo.arguments) else {
                    return
                }
                wheel?.showDemo(scenario)
            } catch {
                logger.error("Demo wheel arguments refused: \(String(describing: error), privacy: .public)")
            }
        #endif
    }
}

extension AppDelegate: WheelControllerDelegate {
    /// Paths stay private in the log (01-prd NFR-6); the summary has none.
    func wheelController(_ controller: WheelController, didSelect selection: WheelSelection) {
        let summary = selection.summary()
        logger.notice("Wheel selection: \(summary, privacy: .public)")
        do {
            let json = String(decoding: try JSONEncoder().encode(selection), as: UTF8.self)
            logger.debug("Wheel selection JSON: \(json, privacy: .private)")
        } catch {
            logger.error("Wheel selection not encodable: \(error.localizedDescription, privacy: .public)")
        }
        #if DEBUG
            hud.show(summary)
        #endif
    }
}
```

`App/StatusMenu.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger
import ZivletWheel

/// Status item and menu (14 §3.1). M2: catalog counts, the bindings line, a DEBUG demo submenu, Quit.
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var wheel: WheelController?

    init(bindings: TriggerBindings, wheel: WheelController) {
        self.wheel = wheel
        super.init()
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Zivlet")
        item.menu = makeMenu(bindings)
    }

    private func makeMenu(_ bindings: TriggerBindings) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(Self.info(StatusSummary.text))
        menu.addItem(Self.info(bindings.menuSummary))
        #if DEBUG
            menu.addItem(.separator())
            menu.addItem(demoItem())
        #endif
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Zivlet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    #if DEBUG
        private func demoItem() -> NSMenuItem {
            let submenu = NSMenu()
            for mode in WheelMode.allCases {
                let entry = NSMenuItem(
                    title: mode.rawValue.capitalized, action: #selector(showDemo(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = mode.rawValue
                submenu.addItem(entry)
            }
            submenu.addItem(.separator())
            let hide = NSMenuItem(title: "Hide wheel", action: #selector(hideDemo), keyEquivalent: "")
            hide.target = self
            submenu.addItem(hide)
            let parent = NSMenuItem(title: "Show wheel (demo)", action: nil, keyEquivalent: "")
            parent.submenu = submenu
            return parent
        }

        @objc private func showDemo(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let mode = WheelMode(rawValue: raw) else { return }
            wheel?.showDemo(.sample(mode))
        }

        @objc private func hideDemo() { wheel?.hide() }
    #endif
}

enum StatusSummary {
    static var text: String {
        "\(ConversionCatalog.standard.pairs.count) conversions · \(ToolID.allCases.count) tools"
    }
}
```

`App/DebugHUD.swift`:

```swift
#if DEBUG
    import AppKit

    /// Dev drop logger surface (05 P0-43): a small non-activating panel at the bottom-right of the main screen that
    /// shows the last selection for 4 s. Debug builds only; Release just logs.
    final class DebugHUD {
        private static let size = NSSize(width: 360, height: 44)
        private let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: DebugHUD.size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        private let label = NSTextField(labelWithString: "")
        private var hideTask: Task<Void, Never>?

        init() {
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
            background.material = .hudWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 12
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.alignment = .center
            label.frame = background.bounds.insetBy(dx: 12, dy: 13)
            background.addSubview(label)
            panel.contentView = background
        }

        func show(_ text: String) {
            label.stringValue = text
            if let visible = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: visible.maxX - Self.size.width - 16, y: visible.minY + 16))
            }
            panel.orderFrontRegardless()
            hideTask?.cancel()
            hideTask = Task { [panel] in
                // Sleep throws only on cancellation, which is the "a newer selection arrived" case.
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                panel.orderOut(nil)
            }
        }
    }
#endif
```

`Scripts/demo-wheel.sh` (needs Screen Recording permission for the terminal that runs it, for `screencapture`):

`Scripts/demo-wheel.sh`:

```bash
#!/usr/bin/env bash
# Debug-build demo check: show the wheel without a drag, capture the main display, confirm the log line.
# Usage: Scripts/demo-wheel.sh convert|tools|actions [glass|solid] [highlight-slot]
# Needs `make app` first, and Screen Recording permission for the terminal (screencapture).
source "$(dirname "$0")/env.sh"
MODE="${1:?usage: demo-wheel.sh convert|tools|actions [glass|solid] [highlight-slot]}"
THEME="${2:-glass}"
SLOT="${3:-0}"
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
OUT="$REPO_ROOT/build/demo-$MODE-$THEME.png"
if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found; run make app" >&2
    exit 1
fi
pkill -x Zivlet || true
open -n "$APP" --args -ZivletDemoWheel "$MODE" -ZivletDemoHighlight "$SLOT" -ZivletWheelTheme "$THEME"
sleep 2
screencapture -x -m "$OUT"
pkill -x Zivlet || true
if /usr/bin/log show --last 30s --style compact --predicate 'subsystem == "app.zivlet.Zivlet"' |
    grep -q "Wheel shown: $MODE, .* slices, $THEME"; then
    echo "OK: $OUT"
else
    echo "error: no 'Wheel shown: $MODE … $THEME' log line" >&2
    exit 1
fi
```

Append to `Makefile` and add `demo` to `.PHONY`:

```make
# Debug only: wheel at screen centre without a drag, screenshot in build/ (MODE=convert|tools|actions THEME=glass|solid).
demo:
	Scripts/demo-wheel.sh "$${MODE:-convert}" "$${THEME:-glass}"
```

### 11.3 Verify green

```bash
chmod +x Scripts/demo-wheel.sh
make format && make lint && make app 2>&1 | grep "BUILD"
xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Release -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- build 2>&1 | grep "BUILD"
nm -U build/DerivedData/Build/Products/Release/Zivlet.app/Contents/MacOS/Zivlet | grep -c DebugHUD
for m in convert tools actions; do make demo MODE=$m; done && make demo MODE=convert THEME=solid
```

| Check | Expected (reference run) |
|---|---|
| `make lint`, `make app`, Release build | exit 0; `** BUILD SUCCEEDED **` twice |
| `nm … grep -c DebugHUD` | `0`: Debug-only code is compiled out of Release |
| `make demo` × 4 | `OK: …/build/demo-<mode>-<theme>.png`; log lines `Wheel shown: convert, 7 slices, glass`, `tools, 9 slices`, `actions, 6 slices`, `convert, 7 slices, solid` |
| Screenshots (open them) | wheel at screen centre; slot 0 highlighted with the accent gradient and grown outward; hub disc with the slot label; labels readable in both themes |
| Status menu (manual) | "275 conversions · 27 tools", "⇧: Convert · ⌘: Tools · ⌃: Actions", Show wheel (demo) ▸ Convert / Tools / Actions / Hide wheel, Quit Zivlet ⌘Q; no Dock icon |
| Idle | `top -l 3 -s 5 -pid $(pgrep -x Zivlet) -stats cpu,idlew` → 0.0 %, 0 idle wake-ups (reference: 25 MB) |

### 11.4 Commit

```bash
git add App Scripts/demo-wheel.sh Makefile
git commit -s -m "feat(app): wire trigger and wheel in an AppKit status-item app with a debug demo"
```

---

## M2-QA — Manual real-drag checklist (owner, on real hardware)

This session cannot synthesize drags (no Accessibility permission), so these rows are manual. Use a Debug build
(`make app`, then open `build/DerivedData/Build/Products/Debug/Zivlet.app`). Watch Console with the filter
`subsystem:app.zivlet.Zivlet`. Use a Force Touch trackpad for haptic rows. Record the results in
`docs/plan/spikes/M2-QA.md` (date, macOS build, Mac model, pass/fail, notes).

| # | Steps | Expected | Covers |
|---|---|---|---|
| Q0 | Launch; open System Settings › Privacy & Security › Accessibility, Input Monitoring, Screen Recording | No prompt at launch or in any row below; Zivlet is listed in none of them | NFR-3, P-T1 |
| Q1 | Drag one `.heic` from Finder; while dragging, tap ⇧ | Convert wheel centred on the pointer within a frame or two: JPG PNG WEBP TIFF AVIF BMP PDF clockwise from 12 o'clock; hub shows name and size | FR-1, FR-3, FR-16, M2 exit |
| Q2 | Same drag, tap ⌘; new drag, tap ⌃ | Tools wheel COMPRESS METADATA EDIT ANNOTATE ADD BG CROP REDACT; actions wheel with AIRDROP at the top | FR-3 |
| Q3 | Move over the petals | Highlight follows (accent gradient, petal grows); hub shows the petal label; one haptic per new petal; a short tick if "Play user interface sound effects" is on, never a buzz on fast sweeps | FR-22, P-W4 |
| Q4 | Release over JPG | HUD "Convert → JPG · 1 item"; Console `Wheel selection: …`; Finder ends the drag normally; the source file is untouched (not moved, no copy) | M2 exit, FR-2 (copy semantics) |
| Q5 | Release over the hub | Finder snaps the icon back; nothing logged | M2 exit |
| Q6 | Open the wheel, then release outside it over another Finder folder | Finder performs its normal move/copy there; the wheel hides at once (`buttonUp`) | 03a T14 |
| Q7 | Hold ⌘ **before** pressing on the file, drag (Finder ⌘-move) | No wheel; release ⌘ and press it again mid-drag → Tools wheel | FR-4, D-3 |
| Q8 | Tap ⇧ (convert opens), tap ⇧ again, tap ⇧ again | Closes, drag continues, reopens at the current pointer | D-2 re-tap |
| Q9 | Tap ⇧, then ⌘ | Morph to Tools at the same anchor, highlight cleared, level-change haptic; releasing keys never closes the wheel | FR-5, FR-6, FR-23 |
| Q10 | Drag a folder: tap ⇧; then ⌃; then ⌘ | ⇧: wheel with pill "Folders work with Actions only"; ⌃: actions wheel; ⌘: shake, pill "No tools for these items" for about 1.2 s, actions wheel stays | FR-25, 03a T9/T12 |
| Q11 | Tap ⇧⌘ together, and ⌥ alone | Nothing happens | FR-3 |
| Q12 | Open the wheel during a Finder drag, press Esc | Wheel closes; the Finder drag continues. If not, Console shows "Esc hot key refused" | P-T3, D-M2-8 |
| Q13 | Put a full-screen app in Split View with a Finder window; drag from Finder, tap ⇧ | Wheel appears over the full-screen Space | 03a §2.1 (`0x159`) |
| Q14 | Open the wheel, swipe to another Space mid-drag | Wheel hides (`spaceChanged`) | 03a T18 |
| Q15 | Two displays (secondary left of or above the main one): drag on the secondary, tap ⇧ near its centre, then near each corner | Wheel on that display at the pointer; near corners the disk moves inside the visible frame (never under the menu bar or Dock), hub offset ≤ 134 pt | FR-24 P1 |
| Q16 | Select text in Safari and drag it; tap ⇧ | No wheel (non-file drag goes passive) | FR-1 |
| Q17 | Hold ⇧ and drag a window by its title bar; click-drag on the Desktop | No wheel | FR-1 |
| Q18 | Accessibility › Display: Reduce Transparency on, repeat Q1; Increase Contrast on; Reduce Motion on | Solid theme for the first two; no bloom or springs under Reduce Motion, only short fades | FR-26, 03a §2.7 |
| Q19 | Leave the app idle 60 s; Activity Monitor › Energy (or `top -stats idlew`) | 0 idle wake-ups, ~0 % CPU | NFR-4, P0-40 |
| Q20 | Glass highlight and convert ↔ tools morph over a full-screen video | No visible hitch; note GPU % in Activity Monitor | P-W1, P-W2 (start) |
| Q21 | Open Actions with ⌃, keep ⌃ held, drop on COPY; repeat holding ⌘ after a ⌘ tap | Drop accepted (copy or generic cursor badge); the source file is never moved | P-T6, 15 C-8 |
| Q22 | Drag an attachment from Mail, tap ⇧ | Known M2 limit: wheel shows "Nothing to work on yet" and refuses the drop (promises are FR-2, P2) | FR-2 (informational) |
| Q23 | Quit, relaunch the Debug build with `open Zivlet.app --args -ZivletFlagsMonitor YES`, repeat Q1 | Record: any prompt? Do taps still work, and do they feel faster? | P-T2 |

M2 passes when Q0–Q11 and Q19 pass (the 05 M2 exit definition). The other rows feed the spikes and P1.

---

## M2 exit check

Run from a fresh clone so nothing generated is reused (any scratch location works):

```bash
git clone "$REPO" "$TMPDIR/zivlet-m2-check" && cd "$TMPDIR/zivlet-m2-check"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make test && make coverage && make lint && make app && make demo && git status --porcelain
```

| Step | Expected (reference run 2026-10-21) |
|---|---|
| `make test` | Seven `✔ Test run with …` lines: 52 (Wheel), 53 (WheelCore), 31 (Trigger), 24 (TriggerHost), 1 (EngineKit), 46 (Core), 31 (EngineMedia) = 238 |
| `make coverage` | Six rows ≥ 80 %: Core 97 %, Trigger 100 %, WheelCore 99 %, EngineMedia 97 %, TriggerHost 88 %, Wheel 94 %; exit 0 |
| `make lint` | no findings; exit 0 |
| `make app` | `** BUILD SUCCEEDED **` |
| `make demo` | `OK: …/build/demo-convert-glass.png` |
| `git status --porcelain` | empty (`build/`, `.build/`, `Zivlet.xcodeproj`, `App/Info.plist` are ignored) |

Then the owner runs M2-QA above. M2 is done when both pass. The follow-ons in index §2.1 do not block M2, except
that P0-31/P0-32 must be **started** (05 §2), which Q12, Q20, Q21 and Q23 do.

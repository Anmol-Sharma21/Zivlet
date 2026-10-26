# 16e — M5b Stream D, part 2: the notch tray (NB6, NB7)

Part of [16-implementation-plan-m5b](16-implementation-plan-m5b.md). Conventions: index §6. How the tray plugs into
the island: [design/19-notch](../design/19-notch.md) §8; look: [design/19c](../design/19c-drop-box-look.md) §3.4,
§4.2–§4.3. Acceptance: 05 row P2-143. Swift below is specification-grade and was not compiled.

The island's rule from design/19 §8 holds throughout: nothing in `ZivletNotchCore` or `ZivletNotch` names jobs,
batches or files. The island learns two new surfaces and how to hand a drag to its client; everything that knows
about boxes is in `ZivletBox`.

---

## Task D8 — `.dropTarget` and `.sensor`; the arbiter ranks visible rests first (D-M5b-6, D-M5b-17)

| Field | Value |
|---|---|
| Goal | `IslandSurface` gains `.dropTarget` (a one-row surface that takes a drop) and `.sensor` (nothing drawn; it takes hover over the housing). `IslandLayout.frame`: `.dropTarget` uses the toast's frame (notch: 360 × housing + 36; pill: 360 × 40); `.sensor` is the housing's rectangle on a notch display and `.zero` (ordered out) on a pill display. `IslandMachine`: a request resting on `.dropTarget` shows it at once and hover does not change it; resting on `.sensor`, hover with the 150 ms intent opens the request's hover surface and the 300 ms grace returns to the sensor, as for a collapsed tab. `IslandArbiter.winner(on:)` picks among requests whose resting surface is visible (not `.hidden`, not `.sensor`) by priority, and only when there is none, the highest-priority sensor. `IslandChrome` draws nothing for `.sensor`. The Notch HUD returns an empty view for both new surfaces (it never asks for them) |
| Acceptance | arbiter tests for every pair: tray sensor + HUD collapsed → HUD; tray drop target + HUD collapsed → tray; tray sensor alone → tray; picker and tray both visible → picker; withdrawing the HUD hands back to the tray's sensor. Layout tests for both surfaces on the recorded and the constructed displays. `IslandMachineTable` gains rows so every event has a row for each new surface; the existing machine, HUD and host tests stay green |
| Effort | M |

**Files:** modify `Sources/ZivletNotchCore/IslandSurface.swift`, `IslandArbiter.swift`, `IslandLayout.swift`,
`IslandMachine.swift`, `IslandMachine+Hover.swift`, `Sources/ZivletNotch/IslandChrome.swift`,
`Sources/ZivletUI/Notch/NotchHUD.swift` (exhaustive switches); tests `Tests/ZivletNotchCoreTests/IslandArbiterTests.swift`,
`IslandLayoutTests.swift`, `IslandMachineTable.swift`, `IslandMachineHoverTests.swift`.

```swift
@Suite("Arbiter: a tray at rest never hides the HUD (D-M5b-6)")
struct IslandArbiterRestTests {
    @Test func theHUDsTabBeatsTheTraysSensor() {
        let a = IslandArbiter().updating(.tray, .tray(.sensor)).updating(.hud, .hud(.collapsed))
        #expect(a.winner(on: 1)?.client == .hud)
    }

    @Test func aDropTargetBeatsTheHUD() {
        let a = IslandArbiter().updating(.hud, .hud(.collapsed)).updating(.tray, .tray(.dropTarget))
        #expect(a.winner(on: 1)?.client == .tray)
    }

    @Test func withoutAVisibleRequestTheSensorWins() {
        let a = IslandArbiter().updating(.tray, .tray(.sensor)).updating(.hud, .hud(.toast)).updating(.hud, nil)
        #expect(a.winner(on: 1) == .tray(.sensor))
    }
}
```

RED: `type 'IslandSurface' has no member 'dropTarget'`. Commit `feat(notch): add the drop-target and sensor surfaces
and rank visible rests first`.

---

## Task D9 — Drop plumbing in the island (D-M5b-7, D-M5b-8)

| Field | Value |
|---|---|
| Goal | `public protocol IslandDropHandling: AnyObject` in `ZivletNotch`: `dragTypes`, `draggingEntered(_:display:) -> NSDragOperation`, `draggingUpdated(_:display:) -> NSDragOperation`, `draggingExited(display:)`, `performDrop(_:display:) -> Bool` (all with `any NSDraggingInfo`: AppKit's type, no file types named). The host's content view forwards the four destination calls to the current client when it adopts the protocol. The host registers the client's `dragTypes` on its content view **only** while the applied surface is `.dropTarget`, and unregisters on any other surface, on close, and at once on `IslandHosts.wheelShown()`. `FakeDraggingInfo` moves to `NotchTestSupport` |
| Acceptance | shell tests on off-screen displays: 0 registered types at rest, the client's types at `.dropTarget`, 0 after the request is withdrawn, 0 right after `wheelShown()` even while the request still says `.dropTarget`; a fake dragging info reaches the client's `performDrop` with the right display; a client that does not adopt the protocol is never registered (the HUD) |
| Effort | M |

**Files:** create `Sources/ZivletNotch/IslandDropHandling.swift`, `Sources/ZivletNotch/IslandContentView.swift`;
modify `Sources/ZivletNotch/IslandHost.swift`, `IslandHost+Events.swift`, `IslandHosts.swift`
(`IslandClientRouter` forwards the drop calls); move `Tests/ZivletBoxTests/FakeDraggingInfo.swift` to
`Tests/NotchTestSupport/FakeDraggingInfo.swift`; create `Tests/ZivletNotchTests/IslandDropTests.swift`.

```swift
@Suite("Island drop plumbing (D-M5b-7, D-M5b-8)")
@MainActor
struct IslandDropTests {
    @Test func dragTypesAreRegisteredOnlyWhileTheTrayAsks() throws {
        let rig = try IslandRig.offScreen()
        let tray = FakeDropClient(types: [.fileURL])
        rig.hosts.register(tray, as: .tray)
        #expect(rig.registeredTypes(on: 1).isEmpty)
        rig.hosts.request(.tray(.dropTarget), from: .tray)
        #expect(rig.registeredTypes(on: 1) == [.fileURL])
        rig.hosts.wheelShown()
        #expect(rig.registeredTypes(on: 1).isEmpty)
    }

    @Test func aDropReachesTheClientWithItsDisplay() throws { /* FakeDraggingInfo → performDrop(display: 1) */ }
}
```

RED: `cannot find type 'IslandDropHandling' in scope`. Commit `feat(notch): let a client take drops while it shows a
drop target`.

---

## Task D10 — `TrayClient` (NB6)

| Field | Value |
|---|---|
| Goal | `TrayClient` in `ZivletBox`, an `IslandClient` and `IslandDropHandling`, registered as `.tray` with the app's one `IslandHosts`. It reacts to: `proximity(.entered(display), itemCount:)` → requests `.dropTarget` on that display (hover surface `.dropTarget`) when `trayWhileDragging` is on and the wheel is not showing; `.left` or `dragEnded()` → back to rest; `wheelShown()` → back to rest and ignores proximity until `wheelHidden()` **and** a new `.entered` (D-M5b-8); box changes → rest is `.sensor` (hover surface `.expanded`) on notch displays while the box has items, else withdrawn (D-M5b-17). Content per surface: `.dropTarget` the 19c §4.2 row ("Add 3", "12 in box"); `.toast` the result; `.expanded` `BoxCompactView`; `.sensor` nothing. Accessibility: label "Drop Box", value the spoken header ("12 items, 84 megabytes"), action "Open Drop Box"; the drop target announces "Add 3 items to the Drop Box". The box behind it is a `TrayBox` port (count, totals, items for the strip, `add(intake:)`, `undoAdd(_:)`, `showPanel(anchor:)`), implemented by `BoxController` |
| Acceptance | with `IslandHosts` on a fake provider and a fake `TrayBox`: entered → the display shows `.dropTarget`; left → `.sensor` (box not empty) or hidden (empty); wheel shown during a drop target → hidden at once, and a later `.entered` before `wheelHidden` does nothing; the setting off → no drop target, the sensor still rests; a pill display never gets a sensor; the D7 failing fakes stay silent through all of it |
| Effort | M |

**Files:** create `Sources/ZivletBox/Tray/TrayClient.swift`, `TrayClient+Content.swift`, `TrayBox.swift`,
`TrayDropRow.swift`; tests `Tests/ZivletBoxTests/TrayClientTests.swift`, `TrayFakes.swift`; modify
`Tests/ZivletBoxTests/PreDropReadTests.swift`.

```swift
@Suite("Tray client (P2-143, D-M5b-8, D-M5b-17)")
@MainActor
struct TrayClientTests {
    @Test func theWheelWinsAndTheTrayWaitsForANewApproach() throws {
        let rig = try TrayRig(boxItems: 12)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
        rig.tray.wheelShown()
        #expect(rig.hosts.surface(on: 1) == .sensor)
        rig.tray.proximity(.entered(display: 1), itemCount: 3)
        #expect(rig.hosts.surface(on: 1) == .sensor)
    }

    @Test func anEmptyBoxLeavesNothingAtTheNotch() throws {
        let rig = try TrayRig(boxItems: 0)
        rig.tray.proximity(.entered(display: 1), itemCount: 2)
        rig.tray.proximity(.left(display: 1), itemCount: 2)
        #expect(rig.hosts.surface(on: 1) == .hidden)
    }
}
```

RED: `cannot find 'TrayClient' in scope`. Commit `feat(box): add the notch tray as a client of the island`.

---

## Task D11 — Tray drop into the current box; compact view; full panel one click away (NB7)

| Field | Value |
|---|---|
| Goal | `performDrop` runs the same `BoxIntake.receive` as the panel (B7) into the current box (OWN-APP-1), then shows the toast "Added 3" with Undo (1.5 s, or 4 s with Undo, as action toasts) and returns to rest; a drop with nothing local shows "Only items stored on this Mac can be added" as a failure toast. Hover on the sensor (or the menu command "Show Progress and Results" when the tray is the winner) opens `BoxCompactView` as the island's expanded content: header, strip of up to 6 thumbnails (type icons first, D-M5b-14), Share and "Open Drop Box". A thumbnail drags its item, the strip's empty space drags all, and the island is held during the drag (`IslandHosts.dragBegan/dragEnded`, D-N13). "Open Drop Box" shows the panel anchored below the island (19c §4.4) and collapses the tray |
| Acceptance | a fake drop of 3 URLs adds 3 to the current box and shows "Added 3"; Undo removes exactly those 3; a refused drop shows the failure toast and adds nothing; the compact view lists the box; "Open Drop Box" calls `showPanel(anchor: .belowIsland)`; a drag from the strip holds the island until it ends |
| Effort | S |

**Files:** create `Sources/ZivletBox/Tray/TrayClient+Drop.swift`; modify `Sources/ZivletBox/Views/BoxCompactView.swift`,
`Sources/ZivletBox/BoxController.swift` (`TrayBox` conformance, `undoAdd`); tests
`Tests/ZivletBoxTests/TrayDropTests.swift`.

RED: `value of type 'TrayClient' has no member 'performDrop'` until the conformance exists. Commit `feat(box): drop
into the box at the notch and open it from there`.

---

## Task D12 — App wiring: tray, samples, zones, wheel, previews (D-M5b-16, D-M5b-20)

| Field | Value |
|---|---|
| Goal | Logic in a testable `TrayDriver` (`ZivletBox`): it owns a `NotchProximity`, a `ShakeDetector` and the wheel state, takes live samples and drag ends, and calls the tray client, the box controller (`showForDrop(at:)` on a shake when `shakeToOpen` is on) and the recorder hook (Debug). `App/BoxWiring.swift` only connects closures: `TriggerHost.onLiveSample`/`onDragEnded` → driver; `IslandHosts.register(tray, as: .tray)` on the hosts `IslandWiring` owns (D-M5a-9); zones from `IslandLayout.trayZone(on:margin:)` for every display, recomputed on the geometry reader's changes; the item count for "Add 3" from the drag pasteboard's item count, read once per change count; wheel show and hide forwarded next to `IslandWiring.wheel(_:)`; settings mapped. Debug-only `-ZivletTrayPreview dropTarget\|toast\|compact\|sensor` (with plan 14's `-ZivletIslandPill YES` and finish flags) logs `Island: <surface>` and `Island: frame …` as the HUD previews do; `check-release-paths.sh` refuses the flag |
| Acceptance | `TrayDriverTests`: samples resting on the housing open the drop target; a shake opens the panel only with the setting on; while the wheel shows, neither fires; a drag end resets both detectors; zones follow a display change. `make app` builds; the release scan refuses the new flag |
| Effort | M |

**Files:** create `Sources/ZivletBox/Tray/TrayDriver.swift`, `Tests/ZivletBoxTests/TrayDriverTests.swift`; modify
`App/BoxWiring.swift`, `App/IslandWiring.swift` (forward the wheel to the tray), `App/AppDelegate.swift`,
`App/IslandShots.swift` (tray preview), `Scripts/check-release-paths.sh`, `Scripts/tests/test-release-flags.sh`.

RED: `cannot find 'TrayDriver' in scope`. Commits `feat(box): drive the tray and shake from live drag samples` and
`feat(app): wire the notch tray into the island and the trigger`.

---

## Task D13 — Tray timing ≤ 50 ms

| Field | Value |
|---|---|
| Goal | `TrayTimingTests.theDropTargetShowsWithin50ms`: hosts built as the app builds them (pre-warmed per display, off screen), a `.entered` from the driver, then the time until the panel is visible at the `.dropTarget` frame, as `NotchHUDTimingTests` measures the HUD (design/19 §9) |
| Acceptance | ≤ 50 ms; on a loaded Mac rerun once by name before calling it a failure (G-M5a-9 records that the HUD's 50 ms test has little margin under load) |
| Effort | S |

**Files:** create `Tests/ZivletBoxTests/TrayTimingTests.swift`.

Commit `test(box): the tray's drop target shows within 50 ms`.

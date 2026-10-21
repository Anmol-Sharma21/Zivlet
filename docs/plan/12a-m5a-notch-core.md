# 12a — M5a part 1: modules, geometry, layout, island machine, arbiter, placement setting, panel and host

Part of [12-implementation-plan-m5a-notch](12-implementation-plan-m5a-notch.md). Conventions: index §5. Design:
[design/19-notch](../design/19-notch.md). Swift below is specification-grade and was not compiled for this plan.

---

## Task N0 — Baseline

| Field | Value |
|---|---|
| Goal | Start from a green `main`: `nice -n 10 make test lint` exit 0. Note the test count per bundle in the session log (the M4 record says 917) |
| Acceptance | both commands exit 0; if not, stop and fix or report before N1 (no M5a code on a red tree) |
| Effort | S (≈ 30 min on a quiet Mac) |

No commit.

---

## Task N1 — `Rect2D` to `ZivletCore`; empty notch modules and test targets (D-N1, D-M5a-1)

| Field | Value |
|---|---|
| Goal | Move `Rect2D` (and its `contains`) from `ZivletWheelCore/PanelPlacer.swift` to `ZivletCore/Shared/Rect2D.swift`, unchanged. Add targets `ZivletNotchCore` (deps `ZivletCore`, `strict`) and `ZivletNotch` (deps `ZivletNotchCore`, `shell`), test targets `ZivletNotchCoreTests` (`strict`) and `ZivletNotchTests` (`shell`), both modules in the `ZivletKit` product, `ZivletUI` depends on `ZivletNotch`, and both in `GATED_MODULES` of `Scripts/coverage.sh` |
| Acceptance | the existing `PanelPlacerTests` and `WheelControllerTests` pass unchanged after the move (imports adjusted only); `make test lint coverage app` pass; coverage lists 15 modules |
| Effort | S |

**Files:** create `Sources/ZivletCore/Shared/Rect2D.swift`, `Sources/ZivletNotchCore/NotchCore.swift` (module doc
comment only), `Sources/ZivletNotch/Notch.swift` (same), `Tests/ZivletNotchCoreTests/Rect2DTests.swift`,
`Tests/ZivletNotchTests/NotchModuleTests.swift`; modify `Package.swift`, `Sources/ZivletWheelCore/PanelPlacer.swift`,
`Sources/ZivletWheel/WheelController.swift` (import), `Tests/ZivletWheelCoreTests/PanelPlacerTests.swift`,
`Tests/ZivletWheelTests/WheelControllerTests.swift` (imports), `Scripts/coverage.sh`.

### N1.1 Tests

```swift
@Suite("Rect2D in ZivletCore (D-M5a-1)")
struct Rect2DTests {
    @Test func containsIsHalfOpenOnTheMaxEdges() {
        let r = Rect2D(x: 0, y: 0, width: 10, height: 10)
        #expect(r.contains(Point2D(x: 0, y: 0)) && !r.contains(Point2D(x: 10, y: 5)))
    }
}

@Suite("ZivletNotch module (D-N1)")
@MainActor
struct NotchModuleTests {
    @Test func theShellModuleSeesTheCore() { #expect(Rect2D(x: 1, y: 2, width: 3, height: 4).maxY == 6) }
}
```

RED: `no such module 'ZivletNotchCore'` until `Package.swift` declares it. The move itself is a refactor: run
`swift test --filter "PanelPlacer|WheelController"` before and after; both green.

Commits `refactor(core): move Rect2D into ZivletCore next to Point2D` and
`chore(notch): add the ZivletNotchCore and ZivletNotch modules to the package and the coverage gate`.

---

## Task N2 — `DisplayGeometry` and `NotchGeometry` with the recorded fixture (design/19 §3.2–§3.3)

| Field | Value |
|---|---|
| Goal | `DisplayGeometry` value (`id`, `frame`, `visibleFrame`, `safeAreaTop`, `auxiliaryTopLeft?`, `auxiliaryTopRight?`; `Sendable`, `Equatable`, `Codable`) with a validating init that rejects non-finite or negative sizes (boundary: values come from AppKit). `NotchGeometry.housing(of:) -> Rect2D?` and `hasNotch(_:)`. Test fixtures `DisplayFixtures.mbp14MoreSpace` (recorded), `noNotch1080`, `safeAreaWithoutAux`, `sideBySide` (constructed, named as such) |
| Acceptance | tests below green; no hard-coded notch size anywhere in `Sources/` |
| Effort | S |

**Files:** create `Sources/ZivletNotchCore/DisplayGeometry.swift`, `Sources/ZivletNotchCore/NotchGeometry.swift`,
`Tests/ZivletNotchCoreTests/DisplayFixtures.swift`, `Tests/ZivletNotchCoreTests/NotchGeometryTests.swift`.

### N2.1 Failing tests first

```swift
enum DisplayFixtures {
    /// Recorded 2026-10-22: 14-inch MacBook Pro (M2 Pro), scaled mode 1800 × 1169 pt, macOS 27.0.
    static func mbp14MoreSpace() throws -> DisplayGeometry {
        try DisplayGeometry(
            id: 1, frame: Rect2D(x: 0, y: 0, width: 1800, height: 1169),
            visibleFrame: Rect2D(x: 0, y: 94, width: 1800, height: 1036), safeAreaTop: 38,
            auxiliaryTopLeft: Rect2D(x: 0, y: 1131, width: 790, height: 38),
            auxiliaryTopRight: Rect2D(x: 1010, y: 1131, width: 790, height: 38))
    }

    /// Constructed: an external 1080p display to the left, with a 25 pt menu bar and no notch.
    static func noNotch1080() throws -> DisplayGeometry {
        try DisplayGeometry(
            id: 2, frame: Rect2D(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: Rect2D(x: -1920, y: 0, width: 1920, height: 1055), safeAreaTop: 0,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
    }
    // safeAreaWithoutAux(), make(leftWidth:rightX:), sideBySide() and all() follow the same pattern.
}
```

The fixtures are throwing functions because the lint configuration forbids `try!` and force unwraps
(`NeverUseForceTry`, `NeverForceUnwrap`), in tests too.

```swift
@Suite("Notch geometry (P2-115, design/19 §3.2)")
struct NotchGeometryTests {
    @Test func housingIsTheGapBetweenTheAuxiliaryAreas() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(NotchGeometry.housing(of: display) == Rect2D(x: 790, y: 1131, width: 220, height: 38))
    }

    @Test func noSafeAreaMeansNoHousing() throws {
        #expect(NotchGeometry.housing(of: try DisplayFixtures.noNotch1080()) == nil)
    }

    @Test func aSafeAreaWithoutAuxiliaryAreasGetsThePill() throws {
        #expect(!NotchGeometry.hasNotch(try DisplayFixtures.safeAreaWithoutAux()))
    }

    @Test func overlappingAuxiliaryAreasMeanNoHousing() throws {
        let display = try DisplayFixtures.make(leftWidth: 900, rightX: 800)
        #expect(NotchGeometry.housing(of: display) == nil)
    }

    @Test func nonFiniteValuesAreRefused() {
        #expect(throws: DisplayGeometry.Invalid.self) {
            try DisplayGeometry(
                id: 9, frame: Rect2D(x: 0, y: 0, width: .nan, height: 10),
                visibleFrame: Rect2D(x: 0, y: 0, width: 10, height: 10), safeAreaTop: 0,
                auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        }
    }

    @Test func geometryRoundTripsThroughJSON() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        let data = try JSONEncoder().encode(display)
        #expect(try JSONDecoder().decode(DisplayGeometry.self, from: data) == display)
    }
}
```

RED: `cannot find 'DisplayGeometry' in scope`. GREEN: `swift test --filter NotchGeometryTests`.

Commit `feat(notch): display geometry and the notch housing from public screen values`.

---

## Task N3 — `IslandLayout` (design/19 §3.4)

| Field | Value |
|---|---|
| Goal | Pure frames per surface and display: `collapsed` = housing plus one ear (= housing height) each side; `ears` (left and right content rectangles, never inside the housing); `toast` = 360 × (housing + 36); `expanded(contentHeight:)` = 380 wide, housing + content, ≤ 320; pill frames on a display without a notch (collapsed 200 × 28, toast 360 × 40, expanded 380 × content ≤ 320, top 6 pt under `visibleFrame.maxY`); all centred and clamped inside the display frame. `display(for: Point2D?, in: [DisplayGeometry])` → the display containing the point, else the first, nil when empty. Constants in `IslandLayout.Metrics` |
| Acceptance | tests below green |
| Effort | S |

**Files:** create `Sources/ZivletNotchCore/IslandLayout.swift`, `Sources/ZivletNotchCore/IslandSurface.swift`
(`enum IslandSurface { case hidden, collapsed, toast, expanded }`), `Tests/ZivletNotchCoreTests/IslandLayoutTests.swift`.

### N3.1 Failing tests first

```swift
@Suite("Island layout (P2-115, design/19 §3.4)")
struct IslandLayoutTests {
    @Test func collapsedIsTheHousingPlusOneEarEachSide() throws {
        let frame = IslandLayout.frame(.collapsed, on: try DisplayFixtures.mbp14MoreSpace())
        #expect(frame == Rect2D(x: 752, y: 1131, width: 296, height: 38))
    }

    @Test func earsSitBesideTheHousingNeverInsideIt() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        let ears = try #require(IslandLayout.ears(on: display))
        #expect(ears.left == Rect2D(x: 752, y: 1131, width: 38, height: 38))
        #expect(ears.right == Rect2D(x: 1010, y: 1131, width: 38, height: 38))
    }

    @Test func toastHangsBelowTheHousing() throws {
        let frame = IslandLayout.frame(.toast, on: try DisplayFixtures.mbp14MoreSpace())
        #expect(frame == Rect2D(x: 720, y: 1095, width: 360, height: 74))
    }

    @Test func expandedHeightFollowsTheContentUpTo320() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(IslandLayout.frame(.expanded, on: display, contentHeight: 108).height == 146)
        #expect(IslandLayout.frame(.expanded, on: display, contentHeight: 900).height == 320)
    }

    @Test func thePillSitsSixPointsUnderTheMenuBar() throws {
        let frame = IslandLayout.frame(.collapsed, on: try DisplayFixtures.noNotch1080())
        #expect(frame == Rect2D(x: -1060, y: 1021, width: 200, height: 28))
    }

    @Test func everyFrameStaysInsideItsDisplay() throws {
        for display in try DisplayFixtures.all() {
            for surface in [IslandSurface.collapsed, .toast, .expanded] {
                let f = IslandLayout.frame(surface, on: display, contentHeight: 400)
                #expect(f.minX >= display.frame.minX && f.maxX <= display.frame.maxX)
                #expect(f.minY >= display.frame.minY && f.maxY <= display.frame.maxY)
            }
        }
    }

    @Test func theDropPointPicksItsDisplayElseTheFirst() throws {
        let displays = try DisplayFixtures.sideBySide()
        #expect(IslandLayout.display(for: Point2D(x: -100, y: 500), in: displays)?.id == 2)
        #expect(IslandLayout.display(for: Point2D(x: 9_000, y: 500), in: displays)?.id == 1)
        #expect(IslandLayout.display(for: nil, in: displays)?.id == 1)
        #expect(IslandLayout.display(for: nil, in: []) == nil)
    }
}
```

RED: `cannot find 'IslandLayout'`. GREEN: `swift test --filter IslandLayoutTests`.

Commit `feat(notch): island frames for the notch and the top-centre pill`.

---

## Task N4 — `IslandMachine` and `IslandMotion` (design/19 §4.1–§4.2, §4.4, §5.1, §5.4)

| Field | Value |
|---|---|
| Goal | A pure value `IslandMachine` with `func handling(_ event: IslandEvent) -> (IslandMachine, [IslandEffect])`. State: the current `IslandRequest?`, `surface`, hover phase (`outside`, `intent(deadline)`, `inside`, `leaving(deadline)`), `suppressed` (wheel), `keyed`. Events (each with `now: Duration`): `request(IslandRequest?)`, `pointerEntered`, `pointerExited`, `tick`, `clicked`, `escape`, `wheelShown`, `wheelHidden`, `displaysChanged([UInt32])`, `accessibilityFocused`. Effects: `show(surface, display, contentHeight)`, `hide`, `schedule(deadline)` (at most one per result), `cancelDeadline`, `becomeKeyAllowed`, `resignKey`, `closeRequested(client)`. `Timing` constants: intent 150 ms, grace 300 ms. `IslandMotion(reduceMotion:)` → `.spring(response: 0.38, damping: 0.78)` / `.spring(0.32, 0.9)` or `.fade(0.18)` (plain values; the shell maps them to SwiftUI) |
| Acceptance | every row of design/19 §4.2 has a test; no `Date`, no clock reads in the module (`grep -n "Date()\|ContinuousClock\|DispatchTime" Sources/ZivletNotchCore` empty) |
| Effort | M |

**Files:** create `Sources/ZivletNotchCore/IslandRequest.swift` (`IslandRequest`, `IslandClientID`),
`Sources/ZivletNotchCore/IslandEvent.swift`, `Sources/ZivletNotchCore/IslandMachine.swift`,
`Sources/ZivletNotchCore/IslandMachine+Hover.swift` (keep each file < 200 lines and each function < 50),
`Sources/ZivletNotchCore/IslandMotion.swift`, `Tests/ZivletNotchCoreTests/IslandMachineTests.swift`,
`Tests/ZivletNotchCoreTests/IslandMachineHoverTests.swift`, `Tests/ZivletNotchCoreTests/IslandMotionTests.swift`.

### N4.1 Failing tests first

```swift
extension IslandRequest {
    static func hud(_ resting: IslandSurface, sticky: Bool = false, display: UInt32 = 1) -> IslandRequest {
        IslandRequest(client: .hud, display: display, resting: resting, hoverSurface: .expanded,
                      contentHeight: 108, sticky: sticky)
    }
}

@Suite("Island machine: requests and surfaces (P2-115, design/19 §4.2)")
struct IslandMachineTests {
    let t0 = Duration.seconds(100)

    @Test func aRequestShowsItsRestingSurface() {
        let (m, effects) = IslandMachine().handling(.request(.hud(.collapsed), now: t0))
        #expect(m.surface == .collapsed)
        #expect(effects.contains(.show(.collapsed, display: 1, contentHeight: 108)))
    }

    @Test func withdrawingTheRequestHidesAndClearsTimers() {
        let shown = IslandMachine().handling(.request(.hud(.collapsed), now: t0)).0
        let (m, effects) = shown.handling(.request(nil, now: t0))
        #expect(m.surface == .hidden && effects.contains(.hide) && effects.contains(.cancelDeadline))
    }

    @Test func aStickyRequestExpandsAtOnceAndStaysAfterThePointerLeaves() {
        var m = IslandMachine().handling(.request(.hud(.expanded, sticky: true), now: t0)).0
        m = m.handling(.pointerEntered(now: t0)).0.handling(.pointerExited(now: t0 + .milliseconds(10))).0
        m = m.handling(.tick(now: t0 + .seconds(5))).0
        #expect(m.surface == .expanded)
    }

    @Test func theWheelCollapsesAHoverExpansionButNotAStickyCard() { /* wheelShown → collapsed; sticky stays */ }
    @Test func hoverIsIgnoredWhileTheWheelIsShown() { /* entered + tick past intent → still collapsed */ }
    @Test func escapeDoesNothingBeforeAClick() { /* escape without clicked → no effects */ }
    @Test func escapeAfterAClickCollapsesAndResignsKey() { /* clicked, escape → resting, .resignKey */ }
    @Test func escapeOnAClosableStickyCardAsksTheClientToClose() { /* → .closeRequested(.hud) */ }
    @Test func aRequestWhoseDisplayIsGoneMovesToTheFirstDisplay() { /* displaysChanged([1]) for display 2 */ }
    @Test func accessibilityFocusExpandsLikeHover() { /* D-M5a-4: no intent delay */ }
    @Test func everyStepSchedulesAtMostOneDeadline() { /* property over a scripted event list */ }
}

@Suite("Island machine: hover intent and grace (design/19 §4.4)")
struct IslandMachineHoverTests {
    let t0 = Duration.seconds(100)

    @Test func hoverExpandsOnlyAfterTheIntentDelay() {
        var m = IslandMachine().handling(.request(.hud(.collapsed), now: t0)).0
        m = m.handling(.pointerEntered(now: t0)).0
        #expect(m.handling(.tick(now: t0 + .milliseconds(149))).0.surface == .collapsed)
        #expect(m.handling(.tick(now: t0 + .milliseconds(150))).0.surface == .expanded)
    }

    @Test func passingThroughOpensNothing() {
        var m = IslandMachine().handling(.request(.hud(.collapsed), now: t0)).0
        m = m.handling(.pointerEntered(now: t0)).0
        let (left, effects) = m.handling(.pointerExited(now: t0 + .milliseconds(80)))
        #expect(effects.contains(.cancelDeadline))
        #expect(left.handling(.tick(now: t0 + .seconds(1))).0.surface == .collapsed)
    }

    @Test func leavingCollapsesAfterTheGrace() { /* expanded by hover, exit at t, tick t+299 ms expanded, t+300 collapsed */ }
    @Test func reenteringDuringTheGraceKeepsItOpen() { /* exit, enter at +100 ms, tick +1 s → expanded */ }
    @Test func aNewRequestWhileHoveredKeepsTheIslandExpanded() { /* toast arrives while hovered → expanded */ }
    @Test func aToastExpandsOnHoverAndReturnsToTheToast() { /* resting .toast, hover → expanded → exit → toast */ }
}

@Suite("Island motion (D-N5)")
struct IslandMotionTests {
    @Test func springsWithoutReduceMotion() {
        #expect(IslandMotion(reduceMotion: false).expand == .spring(response: 0.38, damping: 0.78))
        #expect(IslandMotion(reduceMotion: false).collapse == .spring(response: 0.32, damping: 0.9))
    }

    @Test func onlyAFadeWithReduceMotion() {
        let motion = IslandMotion(reduceMotion: true)
        #expect(motion.expand == .fade(seconds: 0.18) && motion.collapse == .fade(seconds: 0.18))
    }
}
```

The bodies marked with comments are written out in the task the same way as the tests above them (Arrange the
machine with events, Act with one event, Assert surface and effects).

RED: `cannot find 'IslandMachine'`. GREEN: `swift test --filter "IslandMachine|IslandMotion"`.

Commit `feat(notch): island state machine with hover intent, grace, wheel suppression and Escape`.

---

## Task N5 — `IslandArbiter` (design/19 §4.1, §8; D-M5a-7)

| Field | Value |
|---|---|
| Goal | Pure value keeping each client's latest request per display; `winner(on display:) -> IslandRequest?` by priority picker > tray > HUD; `updating(_ client:, _ request: IslandRequest?) -> IslandArbiter`; the machine receives `.request(winner)` whenever the winner on a display changes |
| Acceptance | tests below green, with fake requests for all three clients |
| Effort | S |

**Files:** create `Sources/ZivletNotchCore/IslandArbiter.swift`, `Tests/ZivletNotchCoreTests/IslandArbiterTests.swift`.

### N5.1 Failing tests first

```swift
@Suite("Island arbiter (P2-115: one island, several users)")
struct IslandArbiterTests {
    @Test func theHighestPriorityRequestWins() {
        let a = IslandArbiter().updating(.hud, .hud(.collapsed)).updating(.tray, .tray(.expanded))
        #expect(a.winner(on: 1)?.client == .tray)
        #expect(a.updating(.picker, .picker(.expanded)).winner(on: 1)?.client == .picker)
    }

    @Test func aWithdrawnHigherRequestHandsBackToTheLowerOne() {
        let a = IslandArbiter().updating(.hud, .hud(.toast)).updating(.tray, .tray(.expanded)).updating(.tray, nil)
        #expect(a.winner(on: 1) == .hud(.toast))
    }

    @Test func requestsAreKeptPerDisplay() {
        let a = IslandArbiter().updating(.hud, .hud(.collapsed, display: 2)).updating(.tray, .tray(.expanded))
        #expect(a.winner(on: 2)?.client == .hud && a.winner(on: 1)?.client == .tray)
    }

    @Test func noRequestsMeansNoWinner() { #expect(IslandArbiter().winner(on: 1) == nil) }
}
```

`IslandRequest.tray(_:)` and `.picker(_:)` are test helpers only; no tray or picker code exists in M5a.

RED: `cannot find 'IslandArbiter'`. GREEN: `swift test --filter IslandArbiterTests`; `make coverage` shows
`ZivletNotchCore` ≥ 80 %.

Commit `feat(notch): arbiter so the HUD, the tray and the picker share one island per display`.

---

## Task N6 — `HUDPlacement`, `HUDGroup`, store key and migration (design/19 §6, OWN-HUD-1 defaults)

| Field | Value |
|---|---|
| Goal | `enum HUDPlacement: String { automatic, notch, nearDrop }` with `resolved(hasBuiltInNotch:)`; `struct HUDGroup { placement = .automatic }`; `Settings.hud`; `SettingsStore` loads and saves `settings.hud.v1` through the existing `load`/`save` helpers; validation accepts every case. A launch argument `-ZivletHUDPlacement notch|nearDrop` overrides for that run only and is never stored (same pattern as `-ZivletRevealResults`, used by the demo) |
| Acceptance | tests below green; `diagnosticsJSON` contains `"hud"`; the stored JSON for the other groups is byte-identical before and after an M4 store is loaded and saved |
| Effort | S |

**Files:** modify `Sources/ZivletSettings/Settings.swift`, `Sources/ZivletSettings/SettingsStore.swift`,
`Sources/ZivletSettings/SettingsValidation.swift`; create `Sources/ZivletSettings/HUDPlacement.swift`,
`Tests/ZivletSettingsTests/HUDPlacementTests.swift`.

### N6.1 Failing tests first

```swift
@Suite("HUD placement setting (OWN-HUD-1, design/19 §6)")
@MainActor
struct HUDPlacementTests {
    /// A private suite per test; never `.standard`, so no test touches the developer's own settings. Reuse the
    /// existing settings tests' helper if it already does this.
    func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "hud-\(UUID().uuidString)"))
    }

    @Test func anM4StoreLoadsWithAutomaticPlacementAndUnchangedGroups() throws {
        let defaults = try freshDefaults()
        let m4 = SettingsStore(defaults: defaults, launchArguments: [:])
        m4.update { $0.with(\.output.revealResults, false) }
        defaults.removeObject(forKey: "settings.hud.v1")      // what an M4 install has
        let reloaded = SettingsStore(defaults: defaults, launchArguments: [:])
        #expect(reloaded.current.hud.placement == .automatic)
        #expect(reloaded.current.output.revealResults == false)
    }

    @Test func automaticResolvesToTheNotchOnlyWithABuiltInNotch() {
        #expect(HUDPlacement.automatic.resolved(hasBuiltInNotch: true) == .notch)
        #expect(HUDPlacement.automatic.resolved(hasBuiltInNotch: false) == .nearDrop)
        #expect(HUDPlacement.nearDrop.resolved(hasBuiltInNotch: true) == .nearDrop)
        #expect(HUDPlacement.notch.resolved(hasBuiltInNotch: false) == .notch)   // the pill on that Mac
    }

    @Test func anExplicitChoiceIsStoredAndReloaded() { /* update to .nearDrop, new store, == .nearDrop */ }
    @Test func anUnreadableGroupFallsBackToAutomatic() { /* store Data("{\"placement\":\"corner\"}") */ }
    @Test func theLaunchArgumentOverridesForOneRunAndIsNotStored() { /* launchArguments: ["ZivletHUDPlacement": "notch"] */ }
    @Test func diagnosticsIncludeThePlacement() { #expect(Settings().diagnosticsJSON.contains("\"placement\"")) }
}
```

RED: `value of type 'Settings' has no member 'hud'`. GREEN: `swift test --filter HUDPlacementTests` and the whole
`ZivletSettingsTests` bundle.

Commit `feat(settings): choose where progress and results show, automatic by default`.

---

## Task N7 — `ZivletNotch`: panel, screen reader, host (D-N2, D-N4, D-N6, D-N7, D-N9; design/19 §5.3–§5.4)

| Field | Value |
|---|---|
| Goal | **`IslandPanel`**: `NSPanel` subclass, `[.borderless, .nonactivatingPanel]`, level `.statusBar`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `isOpaque = false`, clear background, `hasShadow = false`, `hidesOnDeactivate = false`, `isMovable = false`, `becomesKeyOnlyIfNeeded = true`, `canBecomeKey` true, `canBecomeMain` false. **`ScreenGeometryReader`**: `DisplayGeometryProvider` over `NSScreen.screens` (id from `NSScreenNumber`), re-read on `didChangeScreenParametersNotification`, publishing on `changes`; the `NSScreen` → value mapping is a static function over plain values so it is testable. **`IslandHost`** (one display): owns a panel, a tracking view (`.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`) and an `NSHostingView` whose root view is `IslandChrome` (the black `IslandShape` with continuous corners, plus the client's content for the surface); applies `IslandEffect`s: expand = set the target frame first, then animate the shape; collapse = animate, then set the smaller frame on completion; hide = fade, then `orderOut` and cancel the deadline task; one `Task.sleep` per scheduled deadline, feeding `.tick`; pre-warms its hosting view once off screen at creation. **`IslandHosts`**: creates a host per display on demand, owns the arbiter and machine per display, forwards client requests, wheel and Reduce Motion events, and posts accessibility announcements given by clients |
| Acceptance | tests below green; idle: a hidden host has no pending task and its panel is not visible |
| Effort | M |

**Files:** create `Sources/ZivletNotch/IslandPanel.swift`, `Sources/ZivletNotch/ScreenGeometryReader.swift`,
`Sources/ZivletNotch/IslandShape.swift`, `Sources/ZivletNotch/IslandChrome.swift`, `Sources/ZivletNotch/IslandHost.swift`,
`Sources/ZivletNotch/IslandHosts.swift`, `Sources/ZivletNotch/IslandClient.swift` (the content protocol:
`func content(for surface: IslandSurface) -> AnyView`, `var accessibilityLabel`, `var accessibilityValue`),
`Tests/ZivletNotchTests/IslandPanelTests.swift`, `Tests/ZivletNotchTests/IslandHostTests.swift`,
`Tests/ZivletNotchTests/ScreenGeometryReaderTests.swift`, `Tests/ZivletNotchTests/FakeDisplays.swift` (a fake provider
whose displays sit at x −5000 so nothing appears on the developer's screen).

### N7.1 Failing tests first

```swift
@Suite("Island panel (D-N2)")
@MainActor
struct IslandPanelTests {
    @Test func nonActivatingAboveTheMenuBarOnEverySpace() {
        let panel = IslandPanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
        #expect(panel.level == .statusBar)
        #expect(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]))
        #expect(!panel.hidesOnDeactivate && !panel.isMovable && !panel.hasShadow)
    }

    @Test func keyOnlyAfterAClickNeverMain() {
        let panel = IslandPanel()
        #expect(panel.canBecomeKey && panel.becomesKeyOnlyIfNeeded && !panel.canBecomeMain)
    }

    @Test func belowTheWheelAndOpenMenus() { #expect(IslandPanel().level.rawValue < NSWindow.Level.popUpMenu.rawValue) }
}

@Suite("Island host (P2-115)")
@MainActor
struct IslandHostTests {
    @Test func showingDoesNotTakeTheKeyWindow() {
        let host = IslandHost(display: FakeDisplays.notch, client: FakeClient())
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        #expect(host.isVisible && !host.isKey)
    }

    @Test func expandingSetsTheLargerFrameBeforeTheAnimation() {
        let host = IslandHost(display: FakeDisplays.notch, client: FakeClient())
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        #expect(host.frame == IslandLayout.frame(.expanded, on: FakeDisplays.notch, contentHeight: 108).cgRect)
    }

    @Test func collapsingShrinksTheFrameWhenTheAnimationCompletes() async {
        let host = IslandHost(display: FakeDisplays.notch, client: FakeClient(), motion: .instant)
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        host.apply([.show(.collapsed, display: 1, contentHeight: 0)])
        await host.animationsSettled()
        #expect(host.frame == IslandLayout.frame(.collapsed, on: FakeDisplays.notch).cgRect)
    }

    @Test func hiddenOrdersOutAndLeavesNoPendingTask() async { /* schedule, then hide → !isVisible, !hasPendingDeadline */ }
    @Test func aDeadlineFeedsOneTickToTheMachine() async { /* schedule now + 10 ms → one .tick observed */ }
    @Test func theHostIsPrewarmed() { #expect(IslandHost(display: FakeDisplays.notch, client: FakeClient()).isPrewarmed) }
    @Test func thePillIsUsedOnADisplayWithoutANotch() { /* FakeDisplays.plain → collapsed frame 200 × 28 */ }
    @Test func hostsAreCreatedPerDisplayOnDemand() { /* IslandHosts with two fake displays: request on 2 → one host */ }
}

@Suite("Screen geometry reader")
@MainActor
struct ScreenGeometryReaderTests {
    @Test func mapsRawScreenValuesToDisplayGeometry() throws {
        let raw = ScreenGeometryReader.Raw(
            number: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            visible: CGRect(x: 0, y: 94, width: 1800, height: 1036), safeTop: 38,
            left: CGRect(x: 0, y: 1131, width: 790, height: 38), right: CGRect(x: 1010, y: 1131, width: 790, height: 38))
        #expect(try ScreenGeometryReader.geometry(raw) == DisplayFixtures.mbp14MoreSpace())
    }

    @Test func aScreenWithInvalidValuesIsSkippedWithOneErrorLine() { /* NaN width → nil, logged once */ }
}
```

`IslandHost` takes an `IslandMotion`-derived animation; tests pass `.instant` so completion runs on the next
main-actor turn. `cgRect` is a small internal `Rect2D` → `CGRect` bridge in `ZivletNotch`.

RED: `cannot find 'IslandPanel'`. GREEN: `swift test --filter "IslandPanel|IslandHost|ScreenGeometryReader"`, then
`make coverage` (`ZivletNotch` ≥ 80 %) and `make app`.

Manual check after GREEN (developer, optional, not a gate): a DEBUG-only launch argument
`-ZivletIslandPreview collapsed|toast|expanded` shows the island with fixed sample content for 5 s so the frame swap
can be seen on the real notch; quit with `osascript -e 'quit app "Zivlet"'`.

Commit `feat(notch): island panel and host above the menu bar on every Space, hover by tracking area only`.

# 08a — M2 tasks 1–3: shell targets, panel placement, wheel model

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 1 — Shell targets `ZivletTriggerHost` and `ZivletWheel`

| Field | Value |
|---|---|
| Goal | Two AppKit/SwiftUI library targets with main-actor default isolation, their test targets, the `ZivletKit` product exporting them, and the coverage gate extended to six modules |
| 05 rows | P0-02 (shell subset; `ZivletUI` arrives with M3) |
| Sources | 02 §4.1 (module table), 02 §5.1 (`ui` settings), 02 §6.1 (isolation), 06a Task 2 (placeholder convention) |

**Files**

| Action | Path |
|---|---|
| modify | `Packages/ZivletKit/Package.swift` |
| create | `Sources/ZivletTriggerHost/ZivletTriggerHostPlaceholder.swift`, `Sources/ZivletWheel/ZivletWheelPlaceholder.swift` (deleted in Tasks 5 and 7) |
| create | `Tests/ZivletTriggerHostTests/ZivletTriggerHostSmokeTests.swift`, `Tests/ZivletWheelTests/ZivletWheelSmokeTests.swift` (deleted in Tasks 5 and 7) |
| modify | `Scripts/coverage.sh` (gated module list) |

### 1.1 Failing tests first

Replace `Package.swift` with the final M2 manifest:

`Packages/ZivletKit/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

// Swift 6 language mode + the upcoming features of 04 §4.2; warnings are errors.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
]
// AppKit/SwiftUI shell modules: main-actor by default (02 §6.1, SE-0466).
let shell: [SwiftSetting] = strict + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "ZivletKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "ZivletKit",
            targets: [
                "ZivletCore", "ZivletTrigger", "ZivletWheelCore", "EngineMedia", "ZivletTriggerHost", "ZivletWheel",
            ])
    ],
    targets: [
        .target(name: "ZivletCore", swiftSettings: strict),
        .target(name: "ZivletTrigger", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletWheelCore", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletTriggerHost", dependencies: ["ZivletTrigger"], swiftSettings: shell),
        .target(name: "ZivletWheel", dependencies: ["ZivletWheelCore", "ZivletTrigger"], swiftSettings: shell),
        .target(name: "ZivletEngineKit", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "EngineMedia", dependencies: ["ZivletEngineKit"], swiftSettings: strict),
        .target(name: "TestSupport", path: "Tests/TestSupport", swiftSettings: strict),

        .testTarget(name: "ZivletCoreTests", dependencies: ["ZivletCore"], swiftSettings: strict),
        .testTarget(
            name: "ZivletTriggerTests", dependencies: ["ZivletTrigger", "TestSupport"], swiftSettings: strict),
        .testTarget(
            name: "ZivletWheelCoreTests", dependencies: ["ZivletWheelCore", "TestSupport"], swiftSettings: strict),
        .testTarget(name: "ZivletTriggerHostTests", dependencies: ["ZivletTriggerHost"], swiftSettings: shell),
        .testTarget(name: "ZivletWheelTests", dependencies: ["ZivletWheel"], swiftSettings: shell),
        .testTarget(name: "ZivletEngineKitTests", dependencies: ["ZivletEngineKit"], swiftSettings: strict),
        .testTarget(
            name: "EngineMediaTests", dependencies: ["EngineMedia"], resources: [.copy("Goldens")],
            swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
```

Smoke tests (the loop writes both):

```bash
cd "$REPO/Packages/ZivletKit"
for m in ZivletTriggerHost ZivletWheel; do
  mkdir -p "Sources/$m" "Tests/${m}Tests"
  cat > "Tests/${m}Tests/${m}SmokeTests.swift" <<EOF
import AppKit
import Testing

@testable import $m

/// Shell modules default to the main actor (SE-0466), so this test body runs on the main thread.
@Test func moduleBuildsOnTheMainActor() {
    #expect(${m}Placeholder.moduleName == "$m")
    #expect(Thread.isMainThread)
}
EOF
done
```

### 1.2 Run, expect failure

`swift test` → `error: 'zivletkit': target 'ZivletTriggerHost' referenced in product 'ZivletKit' is empty`.

### 1.3 Implement

```bash
for m in ZivletTriggerHost ZivletWheel; do
  cat > "Sources/$m/${m}Placeholder.swift" <<EOF
/// Placeholder so the target builds. Deleted by the first real file in this module.
enum ${m}Placeholder {
    static let moduleName = "$m"
}
EOF
done
cd "$REPO" && sed -i '' 's/EngineMedia}"/EngineMedia ZivletTriggerHost ZivletWheel}"/' Scripts/coverage.sh
grep GATED_MODULES= Scripts/coverage.sh
```

Expected `grep` output:
`GATED_MODULES="${GATED_MODULES:-ZivletCore ZivletTrigger ZivletWheelCore EngineMedia ZivletTriggerHost ZivletWheel}"`.

### 1.4 Verify green

`swift test 2>&1 | grep -E "Test run with|error: "` → seven `✔ Test run with …` lines, 135 tests: 24 (WheelCore),
31 (Trigger), 46 (Core), 31 (EngineMedia) and three 1-test lines (EngineKit and the two smoke tests). `make coverage`
exits 0.

### 1.5 Commit

```bash
git add Packages/ZivletKit Scripts/coverage.sh
git commit -s -m "chore(package): add ZivletTriggerHost and ZivletWheel shell targets"
```

---

## Task 2 — Pure panel placement (P0-26)

| Field | Value |
|---|---|
| Goal | `PanelPlacer.place(pointer:screens:)`: pick the screen under the pointer (else the first), centre the wheel on the pointer, and move it only so the disk (r 125.92) plus an 8 pt margin stays inside `visibleFrame`. The 372 pt panel may overhang |
| 05 rows | P0-26 (as amended by 03a §2.1 and 01-prd FR-24 P1; index D-M2-2) |
| Sources | 03a §2.1 Placement, 01-prd FR-24, 07 finding 4 (improves on a centre-clamp placement) |

**Files:** create `Sources/ZivletWheelCore/PanelPlacer.swift` (`Rect2D`, `ScreenFrame`, `PanelPlacement`,
`PanelPlacer`) and `Tests/ZivletWheelCoreTests/PanelPlacerTests.swift`.

### 2.1 Failing tests first

Cases: centred mid-screen; four corners of a 1440 × 900 laptop with a 25 pt menu bar; menu bar only; panel overhang
while the disk fits; a second display at negative x with a left Dock; pointer off every screen; a visible frame
smaller than the disk; no screens; half-open rectangle containment.

`Packages/ZivletKit/Tests/ZivletWheelCoreTests/PanelPlacerTests.swift`:

```swift
import ZivletCore
import Testing

@testable import ZivletWheelCore

@Suite("Panel placement (P0-26, 03a §2.1)")
struct PanelPlacerTests {
    let placer = PanelPlacer()
    /// 1440 × 900 laptop: 25 pt menu bar on top, no Dock reserve.
    let laptop = ScreenFrame(
        frame: Rect2D(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: Rect2D(x: 0, y: 0, width: 1440, height: 875))
    /// 1920 × 1080 display to the left of the laptop, Dock on its left edge (80 pt).
    let leftDisplay = ScreenFrame(
        frame: Rect2D(x: -1920, y: -180, width: 1920, height: 1080),
        visibleFrame: Rect2D(x: -1840, y: -180, width: 1840, height: 1080))

    /// Disk radius 125.92 plus the 8 pt margin.
    let reach = 133.92

    @Test func centresOnThePointerAwayFromEdges() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 700, y: 400), screens: [laptop]))
        #expect(p.screenIndex == 0)
        #expect(p.wheelCentre == Point2D(x: 700, y: 400))
        #expect(p.offset == .zero)
        #expect(p.panelFrame == Rect2D(x: 514, y: 214, width: 372, height: 372))
    }

    @Test(arguments: [
        (Point2D(x: 5, y: 5), Point2D(x: 133.92, y: 133.92)),
        (Point2D(x: 1435, y: 5), Point2D(x: 1306.08, y: 133.92)),
        (Point2D(x: 5, y: 870), Point2D(x: 133.92, y: 741.08)),
        (Point2D(x: 1435, y: 870), Point2D(x: 1306.08, y: 741.08)),
    ])
    func clampsTheDiskIntoTheVisibleFrameAtCorners(pointer: Point2D, centre: Point2D) throws {
        let p = try #require(placer.place(pointer: pointer, screens: [laptop]))
        #expect(abs(p.wheelCentre.x - centre.x) < 1e-9 && abs(p.wheelCentre.y - centre.y) < 1e-9)
        #expect(abs(p.offset.x) <= reach && abs(p.offset.y) <= reach)
    }

    @Test func menuBarPushesTheWheelDownOnly() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 700, y: 890), screens: [laptop]))
        #expect(p.wheelCentre.x == 700)
        #expect(abs(p.wheelCentre.y - (875 - reach)) < 1e-9)
    }

    @Test func panelMayOverhangTheScreenWhileTheDiskFits() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 140, y: 400), screens: [laptop]))
        #expect(p.wheelCentre.x == 140)
        #expect(p.panelFrame.minX < 0)
    }

    @Test func picksTheScreenUnderThePointerWithNegativeOrigins() throws {
        let p = try #require(
            placer.place(pointer: Point2D(x: -1900, y: -170), screens: [laptop, leftDisplay]))
        #expect(p.screenIndex == 1)
        #expect(abs(p.wheelCentre.x - (-1840 + reach)) < 1e-9)
        #expect(abs(p.wheelCentre.y - (-180 + reach)) < 1e-9)
    }

    @Test func pointerOffEveryScreenFallsBackToTheFirst() throws {
        let p = try #require(placer.place(pointer: Point2D(x: 5000, y: 5000), screens: [laptop, leftDisplay]))
        #expect(p.screenIndex == 0)
        #expect(abs(p.wheelCentre.x - (1440 - reach)) < 1e-9)
    }

    @Test func tinyVisibleFrameCentresTheDisk() throws {
        let tiny = ScreenFrame(
            frame: Rect2D(x: 0, y: 0, width: 200, height: 200),
            visibleFrame: Rect2D(x: 0, y: 0, width: 200, height: 200))
        let p = try #require(placer.place(pointer: Point2D(x: 10, y: 190), screens: [tiny]))
        #expect(p.wheelCentre == Point2D(x: 100, y: 100))
    }

    @Test func noScreensGivesNoPlacement() {
        #expect(placer.place(pointer: .zero, screens: []) == nil)
    }

    @Test func rectContainmentIsHalfOpen() {
        let r = Rect2D(x: 0, y: 0, width: 10, height: 10)
        #expect(r.contains(Point2D(x: 0, y: 0)) && r.contains(Point2D(x: 9.99, y: 9.99)))
        #expect(!r.contains(Point2D(x: 10, y: 5)) && !r.contains(Point2D(x: 5, y: 10)))
        #expect(r.midX == 5 && r.maxY == 10)
    }
}
```

### 2.2 Run, expect failure

`swift test --filter ZivletWheelCoreTests` → `error: cannot find 'PanelPlacer' in scope` (also `Rect2D`,
`ScreenFrame`).

### 2.3 Implement (complete)

`Packages/ZivletKit/Sources/ZivletWheelCore/PanelPlacer.swift`:

```swift
import ZivletCore

/// Axis-aligned rectangle in global points, AppKit orientation (origin bottom-left). Keeps WheelCore free of CoreGraphics.
public struct Rect2D: Sendable, Hashable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Half-open on the max edges, so a point on the seam between two displays belongs to one of them.
    public func contains(_ p: Point2D) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
}

/// One display as the placer sees it: full frame and the frame minus menu bar and Dock.
public struct ScreenFrame: Sendable, Equatable {
    public let frame: Rect2D
    public let visibleFrame: Rect2D

    public init(frame: Rect2D, visibleFrame: Rect2D) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public struct PanelPlacement: Sendable, Equatable {
    public let screenIndex: Int
    /// Wheel centre in global points; equals the pointer unless the disk had to move inside the visible frame.
    public let wheelCentre: Point2D
    /// The 372 pt panel centred on `wheelCentre`. It may overhang the screen; only the disk is kept inside.
    public let panelFrame: Rect2D
    /// `wheelCentre − pointer`; zero away from screen edges.
    public let offset: Point2D
}

/// Pure placement (03a §2.1, 01-prd FR-24 P1): centre on the pointer, shift only so the disk (r 125.92) plus an 8 pt
/// margin stays inside the screen's `visibleFrame`.
public struct PanelPlacer: Sendable {
    public let geometry: WheelGeometry
    public let margin: Double

    public init(geometry: WheelGeometry = .standard, margin: Double = 8) {
        self.geometry = geometry
        self.margin = margin
    }

    /// The screen containing the pointer, else the first screen (the menu-bar screen). Nil when there are no screens.
    public func place(pointer: Point2D, screens: [ScreenFrame]) -> PanelPlacement? {
        guard !screens.isEmpty else { return nil }
        let index = screens.firstIndex { $0.frame.contains(pointer) } ?? 0
        let visible = screens[index].visibleFrame
        let reach = geometry.ringOuter + margin
        let centre = Point2D(
            x: clamp(pointer.x, low: visible.minX + reach, high: visible.maxX - reach),
            y: clamp(pointer.y, low: visible.minY + reach, high: visible.maxY - reach))
        let side = geometry.panelSide
        let frame = Rect2D(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        let offset = Point2D(x: centre.x - pointer.x, y: centre.y - pointer.y)
        return PanelPlacement(screenIndex: index, wheelCentre: centre, panelFrame: frame, offset: offset)
    }

    /// When the visible frame is narrower than the disk, the disk is centred on it.
    private func clamp(_ value: Double, low: Double, high: Double) -> Double {
        guard low <= high else { return (low + high) / 2 }
        return min(max(value, low), high)
    }
}
```

### 2.4 Verify green

`swift test --filter ZivletWheelCoreTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 33 tests in 4 suites passed`.

### 2.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletWheelCore/PanelPlacer.swift \
        Packages/ZivletKit/Tests/ZivletWheelCoreTests/PanelPlacerTests.swift
git commit -s -m "feat(wheel): add pure panel placement that keeps the disk on screen"
```

---

## Task 3 — `WheelModel` reducer, hub label, `WheelSelection` (P0-27)

| Field | Value |
|---|---|
| Goal | Immutable `WheelModel` (mode, content, idle hub text, highlight) with `applying(_:)` that returns `self` when nothing changes, `switching(to:content:)` that clears the highlight, `hit(_:)` with hysteresis, `dropTarget`, and `selection(urls:)`. `HubLabel` and `ByteSize` give the idle hub text. `WheelSelection` is the typed drop result (index D-M2-3). `WheelSlice` gets a public initializer so shell tests can build 1…12-slot wheels |
| 05 rows | P0-27, the selection part of P0-43 |
| Sources | 02 §7.7, 03a §2.4 (highlight only on slot change), 03a §2.6 (hub label), 01-prd FR-6 (switch clears highlight) |

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletWheelCore/WheelModel.swift`, `HubLabel.swift`, `WheelSelection.swift` |
| modify | `Sources/ZivletWheelCore/WheelContent.swift` (public `WheelSlice.init`) |
| create | `Tests/ZivletWheelCoreTests/WheelModelTests.swift`, `Tests/ZivletWheelCoreTests/HubLabelTests.swift` |

### 3.1 Failing tests first

`Packages/ZivletKit/Tests/ZivletWheelCoreTests/WheelModelTests.swift`:

```swift
import Foundation
import ZivletCore
import Testing

@testable import ZivletWheelCore

@Suite("Wheel model reducer and selection (P0-27, 03a §2.4–2.6)")
struct WheelModelTests {
    let builder = SliceBuilder()
    var png: WheelModel {
        WheelModel(
            mode: .convert, content: builder.content(for: .convert, items: [SelectionItem(.png)]),
            idleHubLabel: "photo.png\n2.2 MB")
    }

    @Test func pointerOnASlotHighlightsItAndTheHubShowsItsLabel() {
        let hot = png.applying(.slot(2))
        #expect(hot.highlighted == 2)
        #expect(hot.hubLabel == "HEIC")
        #expect(hot.dropTarget == .convert(.heic))
    }

    @Test func hubAndOutsideClearTheHighlightAndRestoreTheIdleLabel() {
        let hot = png.applying(.slot(0))
        #expect(hot.applying(.hub).highlighted == nil)
        #expect(hot.applying(.outside).hubLabel == "photo.png\n2.2 MB")
        #expect(hot.applying(.hub).dropTarget == nil)
    }

    @Test func unchangedHitReturnsAnEqualValue() {
        let hot = png.applying(.slot(1))
        #expect(hot.applying(.slot(1)) == hot)
    }

    @Test func outOfRangeSlotAndEmptyWheelNeverHighlight() {
        #expect(png.applying(.slot(99)).highlighted == nil)
        let empty = WheelModel(mode: .tools, content: .empty(.noTools(.srt)), idleHubLabel: "x")
        #expect(empty.applying(.slot(0)).highlighted == nil)
        #expect(empty.dropTarget == nil)
    }

    @Test func switchingModeClearsTheHighlightAndKeepsTheHubLabel() {
        let hot = png.applying(.slot(0))
        let tools = hot.switching(to: .tools, content: builder.content(for: .tools, items: [SelectionItem(.png)]))
        #expect(tools.mode == .tools && tools.highlighted == nil)
        #expect(tools.idleHubLabel == "photo.png\n2.2 MB")
        #expect(tools.slices.first?.target == .tool(.shrink))
    }

    @Test func hitUsesTheCurrentHighlightForHysteresis() {
        // Seven slots: span ≈ 51.4°. Just past the 0|1 boundary, 2° in: still slot 0 while it is current.
        let span = 2 * Double.pi / 7
        let angle = Double.pi / 2 - (span / 2 + 2 * .pi / 180)
        let p = Point2D(x: 90 * cos(angle), y: 90 * sin(angle))
        #expect(png.hit(p) == .slot(1))
        #expect(png.applying(.slot(0)).hit(p) == .slot(0))
    }

    @Test func dropBuildsATypedSelection() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        let selection = try #require(png.applying(.slot(0)).selection(urls: urls))
        #expect(selection == WheelSelection(mode: .convert, target: .convert(.jpg), urls: urls))
        #expect(selection.summary() == "Convert → JPG · 2 items")
        #expect(png.selection(urls: urls) == nil)
        #expect(png.applying(.slot(0)).selection(urls: []) == nil)
    }

    @Test func selectionSummariesNameToolsAndActions() {
        let one = [URL(fileURLWithPath: "/tmp/clip.mov")]
        #expect(WheelSelection(mode: .tools, target: .tool(.videoTrim), urls: one).summary() == "Tools → TRIM · 1 item")
        #expect(
            WheelSelection(mode: .actions, target: .action(.copyFilePath), urls: one).summary()
                == "Actions → COPY PATH · 1 item")
    }

    @Test func selectionRoundTripsThroughJSON() throws {
        let selection = WheelSelection(
            mode: .tools, target: .tool(.shrink), urls: [URL(fileURLWithPath: "/tmp/a b.png")])
        let data = try JSONEncoder().encode(selection)
        #expect(try JSONDecoder().decode(WheelSelection.self, from: data) == selection)
    }

    @Test func slicesCanBeBuiltDirectlyForShellTests() {
        let slice = WheelSlice(id: "convert.png", label: "PNG", symbolName: nil, target: .convert(.png), badge: nil)
        let model = WheelModel(mode: .convert, content: .slices([slice]), idleHubLabel: "x", highlighted: 0)
        #expect(model.highlightedSlice == slice)
        #expect(
            WheelModel(mode: .convert, content: .slices([slice]), idleHubLabel: "x", highlighted: 3).highlighted == nil)
    }
}
```

Hub text follows 03a §2.6. Sizes are decimal like Finder: one decimal below 10, whole numbers above, POSIX digits, no
grouping, so the tests do not depend on the locale.

`Packages/ZivletKit/Tests/ZivletWheelCoreTests/HubLabelTests.swift`:

```swift
import ZivletCore
import Testing

@testable import ZivletWheelCore

@Suite("Hub label and byte sizes (03a §2.6)")
struct HubLabelTests {
    func file(_ name: String, _ format: FormatID?, _ bytes: Int64? = 1_000) -> HubItem {
        HubItem(name: name, format: format, kind: .file, byteCount: bytes)
    }
    func folder(_ name: String) -> HubItem { HubItem(name: name, format: nil, kind: .folder, byteCount: nil) }

    @Test func oneFileShowsNameAndSize() {
        #expect(HubLabel.text(for: [file("Sunset.heic", .heic, 2_240_000)]) == "Sunset.heic\n2.2 MB")
        #expect(HubLabel.text(for: [file("Sunset.heic", .heic, nil)]) == "Sunset.heic")
    }

    @Test func severalFilesOfOneTypeShowCountTypeAndTotal() {
        let items = [file("a.png", .png, 30_000_000), file("b.png", .png, 18_000_000)]
        #expect(HubLabel.text(for: items) == "2 PNG FILES\n48 MB")
        #expect(HubLabel.text(for: [file("a.gz", .gz), file("b.gz", .gz)]) == "2 GZIP FILES\n2.0 KB")
    }

    @Test func mixedFilesFoldersAndEmpty() {
        #expect(HubLabel.text(for: [file("a.png", .png), file("b.mov", .mov)]) == "MIXED\n2.0 KB")
        #expect(HubLabel.text(for: [file("a.png", .png), file("x", nil)]) == "MIXED\n2.0 KB")
        #expect(HubLabel.text(for: [folder("Photos")]) == "FOLDER")
        #expect(HubLabel.text(for: [folder("A"), folder("B"), folder("C")]) == "3 FOLDERS")
        #expect(HubLabel.text(for: [folder("A"), file("a.png", .png)]) == "2 ITEMS")
        #expect(HubLabel.text(for: []) == "")
    }

    @Test func unknownSizeDropsTheSizeLine() {
        #expect(HubLabel.text(for: [file("a.png", .png), file("b.png", .png, nil)]) == "2 PNG FILES")
    }

    @Test(arguments: [
        (Int64(0), "Zero bytes"), (1, "1 byte"), (999, "999 bytes"), (1_000, "1.0 KB"), (2_240_000, "2.2 MB"),
        (48_000_000, "48 MB"), (999_449, "999 KB"), (999_500, "1.0 MB"), (9_960_000, "10 MB"),
        (5_000_000_000_000, "5.0 TB"), (12_000_000_000_000_000, "12000 TB"),
    ])
    func byteSizesUseDecimalUnits(bytes: Int64, text: String) {
        #expect(ByteSize.text(bytes) == text)
    }
}
```

### 3.2 Run, expect failure

`swift test --filter ZivletWheelCoreTests` → `error: cannot find 'HubLabel' in scope` (also `HubItem`, `ByteSize`,
`WheelModel`, `WheelSelection`).

### 3.3 Implement (complete)

In `WheelContent.swift`, add a public initializer to `WheelSlice` (the stored properties are unchanged):

```swift
    public init(id: String, label: String, symbolName: String?, target: SliceTarget, badge: String?) {
        self.id = id
        self.label = label
        self.symbolName = symbolName
        self.target = target
        self.badge = badge
    }
```

`Packages/ZivletKit/Sources/ZivletWheelCore/WheelModel.swift`:

```swift
import Foundation
import ZivletCore

/// Immutable wheel state (02 §7.7, 05 P0-27). Every change builds a new value; an unchanged hit returns `self`, so a
/// store that compares values re-renders only when the highlighted slot really changes (03a §2.4).
public struct WheelModel: Sendable, Equatable {
    public let mode: WheelMode
    public let content: WheelContent
    public let idleHubLabel: String
    public let highlighted: Int?

    public init(mode: WheelMode, content: WheelContent, idleHubLabel: String, highlighted: Int? = nil) {
        self.mode = mode
        self.content = content
        self.idleHubLabel = idleHubLabel
        self.highlighted = highlighted.flatMap { content.slices.indices.contains($0) ? $0 : nil }
    }

    public var slices: [WheelSlice] { content.slices }
    public var highlightedSlice: WheelSlice? { highlighted.map { slices[$0] } }
    /// Hovering a slot shows its label in the hub; otherwise the idle text.
    public var hubLabel: String { highlightedSlice?.label ?? idleHubLabel }
    /// Nil → refuse the drop and let the source snap back (hub, outside, empty wheel).
    public var dropTarget: SliceTarget? { highlightedSlice?.target }

    /// Hit-test a point relative to the wheel centre (y up) with hysteresis against the current highlight.
    public func hit(_ point: Point2D, tester: WheelHitTester = WheelHitTester()) -> HitResult {
        tester.hitTest(point, count: slices.count, current: highlighted)
    }

    public func applying(_ hit: HitResult) -> WheelModel {
        let next = Self.slot(of: hit).flatMap { slices.indices.contains($0) ? $0 : nil }
        guard next != highlighted else { return self }
        return WheelModel(mode: mode, content: content, idleHubLabel: idleHubLabel, highlighted: next)
    }

    /// In-place mode switch: same anchor and hub text, highlight cleared (01-prd FR-6).
    public func switching(to mode: WheelMode, content: WheelContent) -> WheelModel {
        WheelModel(mode: mode, content: content, idleHubLabel: idleHubLabel)
    }

    public func selection(urls: [URL]) -> WheelSelection? {
        guard let target = dropTarget, !urls.isEmpty else { return nil }
        return WheelSelection(mode: mode, target: target, urls: urls)
    }

    private static func slot(of hit: HitResult) -> Int? {
        if case .slot(let index) = hit { return index }
        return nil
    }
}
```

`Packages/ZivletKit/Sources/ZivletWheelCore/HubLabel.swift`:

```swift
import Foundation
import ZivletCore

/// One dragged item as the hub label sees it. `byteCount` is nil for folders and unreadable items.
public struct HubItem: Sendable, Equatable {
    public let name: String
    public let format: FormatID?
    public let kind: SelectionItemKind
    public let byteCount: Int64?

    public init(name: String, format: FormatID?, kind: SelectionItemKind, byteCount: Int64?) {
        self.name = name
        self.format = format
        self.kind = kind
        self.byteCount = byteCount
    }
}

/// Idle hub text (03a §2.6): one file → name + size; n files of one type → "<n> <TYPE> FILES" + total; other files →
/// "MIXED" + total; folders → "FOLDER" / "<n> FOLDERS"; files and folders → "<n> ITEMS".
public enum HubLabel {
    public static func text(for items: [HubItem], registry: FormatRegistry = .standard) -> String {
        guard let first = items.first else { return "" }
        let folders = items.count { $0.kind == .folder }
        if folders == items.count { return folders == 1 ? "FOLDER" : "\(folders) FOLDERS" }
        if folders > 0 { return "\(items.count) ITEMS" }
        let headline: String
        if items.count == 1 {
            headline = first.name
        } else if let format = first.format, items.allSatisfy({ $0.format == format }) {
            headline = "\(items.count) \(registry.format(format).wheelLabel) FILES"
        } else {
            headline = "MIXED"
        }
        return [headline, totalSize(items)].compactMap { $0 }.joined(separator: "\n")
    }

    /// Nil unless every size is known, so the hub never shows a partial total.
    private static func totalSize(_ items: [HubItem]) -> String? {
        let sizes = items.compactMap(\.byteCount)
        guard sizes.count == items.count else { return nil }
        return ByteSize.text(sizes.reduce(0, +))
    }
}

/// Decimal (1000-based) sizes like Finder: one decimal below 10, whole numbers above, POSIX digits.
public enum ByteSize {
    static let units = ["KB", "MB", "GB", "TB"]

    public static func text(_ bytes: Int64) -> String {
        switch bytes {
        case ...0: "Zero bytes"
        case 1: "1 byte"
        case 2..<1_000: "\(bytes) bytes"
        default: scaled(Double(bytes) / 1_000, unit: 0)
        }
    }

    private static func scaled(_ value: Double, unit: Int) -> String {
        let tenths = (value * 10).rounded() / 10
        if tenths < 10 { return String(format: "%.1f %@", tenths, units[unit]) }
        let whole = value.rounded()
        if whole >= 1_000, unit < units.count - 1 { return scaled(value / 1_000, unit: unit + 1) }
        return "\(Int64(whole)) \(units[unit])"
    }
}
```

`Packages/ZivletKit/Sources/ZivletWheelCore/WheelSelection.swift`:

```swift
import Foundation
import ZivletCore

/// What a drop on a slice asks for. M2 logs it; M3 turns it into a job request.
public struct WheelSelection: Sendable, Equatable, Codable {
    public let mode: WheelMode
    public let target: SliceTarget
    public let urls: [URL]

    public init(mode: WheelMode, target: SliceTarget, urls: [URL]) {
        self.mode = mode
        self.target = target
        self.urls = urls
    }

    /// One line for logs and the dev HUD, for example "Convert → JPG · 2 items". Contains no paths.
    public func summary(registry: FormatRegistry = .standard, tools: ToolCatalog = .standard) -> String {
        let count = urls.count == 1 ? "1 item" : "\(urls.count) items"
        return "\(Self.title(mode)) → \(label(registry: registry, tools: tools)) · \(count)"
    }

    private func label(registry: FormatRegistry, tools: ToolCatalog) -> String {
        switch target {
        case .convert(let format): registry.format(format).wheelLabel
        case .tool(let tool): tools.spec(tool).wheelLabel
        case .action(let action): action.wheelLabel
        }
    }

    private static func title(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: "Convert"
        case .tools: "Tools"
        case .actions: "Actions"
        }
    }
}
```

### 3.4 Verify green

`swift test --filter ZivletWheelCoreTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 48 tests in 6 suites passed`.

### 3.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletWheelCore Packages/ZivletKit/Tests/ZivletWheelCoreTests
git commit -s -m "feat(wheel): add WheelModel reducer, hub label and typed WheelSelection"
```

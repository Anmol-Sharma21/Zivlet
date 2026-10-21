# 06d — M1 task 7: wheel geometry, hit-testing and slice lists

Part of [06-implementation-plan-m1](06-implementation-plan-m1.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 7 — `ZivletWheelCore`: geometry, hit-test, slice derivation

| Field | Value |
|---|---|
| Goal | Pure wheel maths and the per-mode slice lists, testable without AppKit or the main actor (index D1) |
| 05 rows | P0-24, P0-25, slice part of P0-15 (panel placement P0-26, reducer P0-27, drag negotiation P0-28 follow later) |
| Sources | 03a §2.2 (geometry), 03a §2.3 (slot order), 03a §2.4 (hit-test), 03a §2.6 (slice lists, empty states) |

Geometry constants (points; 03a §2.2):

| Element | Value | Element | Value |
|---|---|---|---|
| Hub hole (drop = cancel) | r 42.24 | Petal inner / outer | r 48.64 / 119.52 |
| Ring (backdrop disk) | r 125.92 | Gap between petals | 4 pt, constant width: inset `asin(min(2/r, 0.95))` at radius r |
| Outer corner | starts 20.16 inside the rim; angular inset `min(0.24·span, 0.15)` | Inner corner | `min(0.18·span, 0.18)` |
| Label radius | 40 + (119.52 − 40) × 0.56 = 84.5312 | Intro radius | 50.4 |
| Outer hit slack | r 150 | Boundary hysteresis | 3° |
| Panel | 372 × 372 | Max slots | 12 |

Slot order: `span = 2π/n`, `base = (n == 3) ? π : π/2`, `centre(k) = base − k·span` (AppKit radians, y up). Slot 0 is at
12 o'clock and slots run clockwise; three slots start at 9 o'clock; one slot is a full ring.

Three TDD cycles, three commits.

### 7a — Geometry

**Files:** create `Sources/ZivletWheelCore/WheelGeometry.swift`, `Tests/ZivletWheelCoreTests/WheelGeometryTests.swift`;
delete `Sources/ZivletWheelCore/ZivletWheelCorePlaceholder.swift` and `Tests/ZivletWheelCoreTests/ZivletWheelCoreSmokeTests.swift`.

#### 7a.1 Failing tests first

```swift
import Foundation
import ZivletCore
import Testing

@testable import ZivletWheelCore

@Suite("Wheel geometry (P0-24, 03a §2.2–2.3)")
struct WheelGeometryTests {
    let g = WheelGeometry.standard

    @Test func constantsMatchDesign() {
        #expect(g.hubRadius == 42.24 && g.petalInner == 48.64 && g.petalOuter == 119.52 && g.ringOuter == 125.92)
        #expect(g.gap == 4 && g.panelSide == 372 && g.maxSlots == 12 && g.outerSlack == 150)
        #expect(abs(g.labelRadius - 84.5312) < 1e-9)
    }

    @Test(arguments: 1...12)
    func slotZeroIsAtTwelveOClockExceptThreeSlots(count: Int) {
        let expected = count == 3 ? Double.pi : .pi / 2
        #expect(abs(g.centreAngle(slot: 0, count: count) - expected) < 1e-12)
    }

    @Test func slotsRunClockwise() {
        #expect(abs(g.centreAngle(slot: 1, count: 4) - 0) < 1e-12)  // 3 o'clock
        #expect(abs(g.centreAngle(slot: 2, count: 4) - -Double.pi / 2) < 1e-12)  // 6 o'clock
        #expect(abs(g.centreAngle(slot: 1, count: 3) - Double.pi / 3) < 1e-12)  // 9 → upper right
        let label = g.labelPoint(slot: 0, count: 6)
        #expect(abs(label.x) < 1e-9 && abs(label.y - g.labelRadius) < 1e-9)
    }

    /// Perpendicular distance from a petal edge to the slot boundary ray is r·sin(inset) = gap/2.
    @Test(arguments: [48.64, 84.5312, 119.52])
    func gapIsFourPointsAtEveryRadius(r: Double) {
        let halfGap = r * sin(g.edgeInset(atRadius: r))
        #expect(abs(2 * halfGap - 4) < 0.01)
    }

    @Test func cornerInsetsAreCapped() {
        let six = g.cornerInsets(count: 6)
        #expect(abs(six.outer - 0.15) < 1e-12 && abs(six.inner - 0.18) < 1e-12)
        let twelve = g.cornerInsets(count: 12)
        #expect(abs(twelve.outer - 0.24 * (2 * .pi / 12)) < 1e-12)
    }
}
```

#### 7a.2 Run, expect failure

`swift test --filter ZivletWheelCoreTests` → `error: cannot find 'WheelGeometry' in scope`.

#### 7a.3 Implement (complete)

```swift
import Foundation
import ZivletCore

/// Wheel constants in points (03a §2.2) and pure angle maths (03a §2.3).
public struct WheelGeometry: Sendable, Equatable {
    public static let standard = WheelGeometry()

    public let hubRadius = 42.24
    public let petalInner = 48.64
    public let petalOuter = 119.52
    public let ringOuter = 125.92
    public let gap = 4.0
    public let outerCornerInset = 20.16
    public let entryRadius = 50.4
    public let outerSlack = 150.0
    public let hysteresis = 3.0 * Double.pi / 180
    public let panelSide = 372.0
    public let maxSlots = 12

    /// 40 + (119.52 − 40) × 0.56 = 84.5312.
    public var labelRadius: Double { 40 + (petalOuter - 40) * 0.56 }

    public func span(count: Int) -> Double { 2 * .pi / Double(max(count, 1)) }

    /// Slot 0 at 12 o'clock, clockwise; three slots start at 9 o'clock.
    public func baseAngle(count: Int) -> Double { count == 3 ? .pi : .pi / 2 }

    /// Centre angle of `slot` in AppKit radians (counter-clockwise from +x).
    public func centreAngle(slot: Int, count: Int) -> Double {
        baseAngle(count: count) - Double(slot) * span(count: count)
    }

    public func labelPoint(slot: Int, count: Int) -> Point2D {
        let a = centreAngle(slot: slot, count: count)
        return Point2D(x: labelRadius * cos(a), y: labelRadius * sin(a))
    }

    /// Half-angle removed at radius r so the gap stays 4 pt wide: asin(min(2/r, 0.95)).
    public func edgeInset(atRadius r: Double) -> Double {
        asin(min((gap / 2) / r, 0.95))
    }

    /// Angular corner insets for the petal outline (outer, inner).
    public func cornerInsets(count: Int) -> (outer: Double, inner: Double) {
        let s = span(count: count)
        return (min(0.24 * s, 0.15), min(0.18 * s, 0.18))
    }
}
```

#### 7a.4 Verify and commit

`swift test --filter ZivletWheelCoreTests` → `✔ Test run with 5 tests in 1 suite passed`.

```bash
git add -A Packages/ZivletKit
git commit -s -m "feat(wheel): add wheel geometry constants and slot angles"
```

### 7b — Hit-testing and petal containment

**Files:** create `Sources/ZivletWheelCore/WheelHitTester.swift`, `Tests/ZivletWheelCoreTests/WheelHitTesterTests.swift`.

Two functions with different jobs:

| Function | Use | Rule |
|---|---|---|
| `hitTest(_:count:current:)` | Drag-time targeting (forgiving) | hub if r < 42.24; outside if r > 150; else the sector centred on the nearest petal, so gaps belong to the nearer slot; keep `current` while within span/2 + 3° of its centre |
| `petalContains(_:slot:count:)` | Exact shape (rendering, exact mode, tests) | 48.64 ≤ r ≤ 119.52 and the angular offset from the slot centre ≤ span/2 − gap inset at r; n = 1 is the whole annulus |

The 10,000-point test pins that both agree: a point inside a petal always hits that petal, and petals never overlap.

#### 7b.1 Failing tests first

```swift
import Foundation
import ZivletCore
import TestSupport
import Testing

@testable import ZivletWheelCore

@Suite("Hit testing (P0-25, 03a §2.4)")
struct WheelHitTesterTests {
    let tester = WheelHitTester()
    let g = WheelGeometry.standard

    func polar(_ r: Double, _ angle: Double) -> Point2D { Point2D(x: r * cos(angle), y: r * sin(angle)) }

    @Test func hubAndOutside() {
        #expect(tester.hitTest(Point2D(x: 10, y: 10), count: 6) == .hub)
        #expect(tester.hitTest(polar(42.23, 1), count: 6) == .hub)
        #expect(tester.hitTest(polar(150.01, 1), count: 6) == .outside)
        #expect(tester.hitTest(polar(140, .pi / 2), count: 6) == .slot(0), "slack beyond the rim still hits")
        #expect(tester.hitTest(polar(80, 0), count: 0) == .outside)
    }

    @Test(arguments: 1...12)
    func everySlotCentreHitsItsSlot(count: Int) {
        for slot in 0..<count {
            let p = polar(g.labelRadius, g.centreAngle(slot: slot, count: count))
            #expect(tester.hitTest(p, count: count) == .slot(slot))
        }
    }

    @Test func threeSlotsStartAtNineOClock() {
        #expect(tester.hitTest(Point2D(x: -80, y: 0), count: 3) == .slot(0))
        #expect(tester.hitTest(Point2D(x: 80, y: 0), count: 4) == .slot(1))
    }

    @Test func gapsBelongToTheNearerSlot() {
        let boundary = g.centreAngle(slot: 0, count: 6) - g.span(count: 6) / 2
        #expect(tester.hitTest(polar(80, boundary + 0.01), count: 6) == .slot(0))
        #expect(tester.hitTest(polar(80, boundary - 0.01), count: 6) == .slot(1))
    }

    @Test func hysteresisKeepsCurrentSlotWithinThreeDegrees() {
        let boundary = g.centreAngle(slot: 0, count: 6) - g.span(count: 6) / 2
        let justPast = polar(80, boundary - 2 * .pi / 180)
        #expect(tester.hitTest(justPast, count: 6, current: 0) == .slot(0))
        #expect(tester.hitTest(justPast, count: 6, current: nil) == .slot(1))
        let wellPast = polar(80, boundary - 4 * .pi / 180)
        #expect(tester.hitTest(wellPast, count: 6, current: 0) == .slot(1))
    }

    @Test func petalContainmentExcludesGapsHubAndRim() {
        let boundary = g.centreAngle(slot: 0, count: 6) - g.span(count: 6) / 2
        #expect(tester.petalContains(polar(80, .pi / 2), slot: 0, count: 6))
        #expect(!tester.petalContains(polar(80, boundary), slot: 0, count: 6))
        #expect(!tester.petalContains(polar(80, boundary), slot: 1, count: 6))
        #expect(!tester.petalContains(polar(45, .pi / 2), slot: 0, count: 6))
        #expect(!tester.petalContains(polar(122, .pi / 2), slot: 0, count: 6))
        #expect(tester.petalContains(polar(100, 4), slot: 0, count: 1), "one slot is a full ring")
    }

    /// Exact containment never disagrees with the forgiving hit test, and petals never overlap.
    @Test func containmentAgreesWithHitTestOnTenThousandPoints() {
        var rng = SplitMix64(seed: 2026)
        for _ in 0..<10_000 {
            let count = Int.random(in: 1...12, using: &rng)
            let p = polar(Double.random(in: 0...160, using: &rng), Double.random(in: 0..<(2 * .pi), using: &rng))
            let owners = (0..<count).filter { tester.petalContains(p, slot: $0, count: count) }
            #expect(owners.count <= 1)
            if let owner = owners.first { #expect(tester.hitTest(p, count: count) == .slot(owner)) }
        }
    }
}
```

#### 7b.2 Run, expect failure

`swift test --filter ZivletWheelCoreTests` → `error: cannot find 'WheelHitTester' in scope`.

#### 7b.3 Implement (complete)

```swift
import Foundation
import ZivletCore

public enum HitResult: Sendable, Equatable {
    case hub  // drop = cancel (snap back)
    case slot(Int)
    case outside
}

/// Pure hit-testing (03a §2.4). Points are relative to the wheel centre, y up.
public struct WheelHitTester: Sendable {
    public let geometry: WheelGeometry
    public init(geometry: WheelGeometry = .standard) { self.geometry = geometry }

    /// Forgiving mode: gaps belong to the nearer slot, slack to r 150, 3° hysteresis against `current`.
    public func hitTest(_ p: Point2D, count: Int, current: Int? = nil) -> HitResult {
        let r = (p.x * p.x + p.y * p.y).squareRoot()
        if r < geometry.hubRadius { return .hub }
        if r > geometry.outerSlack || count < 1 { return .outside }
        let a = clockwiseAngle(p, count: count)
        let span = geometry.span(count: count)
        let slot = Int((a / span).rounded(.toNearestOrAwayFromZero)) % count
        if let current, current != slot, current < count,
            angularDistance(a, Double(current) * span) < span / 2 + geometry.hysteresis
        {
            return .slot(current)
        }
        return .slot(slot)
    }

    /// Exact petal containment (03a §2.4): inside the petal annulus and outside both 4 pt gap bands.
    public func petalContains(_ p: Point2D, slot: Int, count: Int) -> Bool {
        let r = (p.x * p.x + p.y * p.y).squareRoot()
        guard r >= geometry.petalInner, r <= geometry.petalOuter, count >= 1 else { return false }
        if count == 1 { return true }
        let offset = angularDistance(clockwiseAngle(p, count: count), Double(slot) * geometry.span(count: count))
        return offset <= geometry.span(count: count) / 2 - geometry.edgeInset(atRadius: r)
    }

    /// Clockwise angle from slot 0's centre, in [0, 2π).
    func clockwiseAngle(_ p: Point2D, count: Int) -> Double {
        let raw = (geometry.baseAngle(count: count) - atan2(p.y, p.x)).truncatingRemainder(dividingBy: 2 * .pi)
        return raw < 0 ? raw + 2 * .pi : raw
    }

    func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
        return min(d, 2 * .pi - d)
    }
}
```

#### 7b.4 Verify and commit

`swift test --filter ZivletWheelCoreTests` → `✔ Test run with 12 tests in 2 suites passed`.

```bash
git add Packages/ZivletKit
git commit -s -m "feat(wheel): add forgiving hit-test with hysteresis and exact petal containment"
```

### 7c — Slice lists per mode, including multi-file mixes

**Files:** create `Sources/ZivletWheelCore/WheelContent.swift`, `Sources/ZivletWheelCore/SliceBuilder.swift`,
`Sources/ZivletWheelCore/SliceBuilder+Convert.swift`, `Tests/ZivletWheelCoreTests/SliceBuilderTests.swift`.

Rules (03a §2.6):

| Mode | Selection | Result |
|---|---|---|
| any | no items | empty: "Nothing to work on yet" [critic3: all copy in this table is Zivlet's own] |
| convert, tools | any item not local/readable | empty: "Zivlet can't read one of these files" |
| actions | any item not local | empty: "Actions work on items stored on this Mac" |
| convert | any plain folder | empty: "Folders work with Actions only" (`.pages`/`.rtfd` packages are files) |
| convert | any item with no known format | empty: "Zivlet doesn't know this file type" |
| convert | one format | `targets(f)` in catalog order, minus capability-gated targets; all gated → "<FMT> needs an engine that isn't installed" |
| convert | several formats, one family | first format's targets that every other format can also produce, in that order; none → "These files can't share a format" |
| convert | several families | union of each family's shared targets, grouped by family in first-appearance order, de-duplicated; badge "k of n" when only k of n items can produce it; > 12 slots → "These files can't share a format" (index D5) |
| tools | files only | `ToolCatalog.tools(for:)` with the total count; none → "No tools for <FMT> files" (one format) or "No tools for these items" |
| tools | any folder or unknown format | "No tools for these items" |
| actions | any local selection, folders included | the 6 actions in fixed order |

`acceptedModes(items:capabilities:)` returns the modes whose content is non-empty; the trigger host puts it in
`DragSummary.acceptedModes`.

#### 7c.1 Failing tests first

```swift
import ZivletCore
import Testing

@testable import ZivletWheelCore

@Suite("Slice lists per mode (03a §2.6)")
struct SliceBuilderTests {
    let builder = SliceBuilder()

    func targets(_ content: WheelContent) -> [SliceTarget] { content.slices.map(\.target) }
    func files(_ formats: FormatID...) -> [SelectionItem] { formats.map { SelectionItem($0) } }

    @Test func singleFormatUsesCatalogOrder() {
        let content = builder.content(for: .convert, items: files(.png))
        #expect(targets(content) == [.jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf].map(SliceTarget.convert))
        #expect(content.slices.first?.label == "JPG" && content.slices.first?.id == "convert.jpg")
    }

    @Test func sameFamilyKeepsFirstFormatsSharedTargets() {
        let content = builder.content(for: .convert, items: files(.jpg, .png, .png))
        #expect(targets(content) == [.webp, .heic, .tiff, .avif, .bmp, .pdf].map(SliceTarget.convert))
        #expect(content.slices.allSatisfy { $0.badge == nil })
    }

    @Test func gifMixesAsVideoAndPdfAsDocument() {
        #expect(
            targets(builder.content(for: .convert, items: files(.mp4, .gif)))
                == [.mov, .mkv, .webm, .avi, .wmv].map(SliceTarget.convert))
        #expect(
            targets(builder.content(for: .convert, items: files(.docx, .pdf)))
                == [.pages, .txt, .md, .epub, .png, .jpg].map(SliceTarget.convert))
    }

    @Test func mixedFamiliesGiveBadgedUnionWhenItFits() {
        let content = builder.content(for: .convert, items: files(.jpg, .srt, .srt))
        #expect(content.slices.count == 9)
        #expect(content.slices.first?.badge == "1 of 3")
        #expect(content.slices.last?.target == .convert(.txt))
        #expect(content.slices.last?.badge == "2 of 3")
    }

    @Test func mixedFamiliesOverTwelveSlotsAreEmpty() {
        #expect(builder.content(for: .convert, items: files(.jpg, .mp3)) == .empty(.noCommonFormat))
    }

    @Test(arguments: [
        ([SelectionItem](), WheelMode.convert, EmptyReason.noItems),
        ([SelectionItem(nil, kind: .folder)], .convert, .foldersCannotConvert),
        ([SelectionItem(.png), SelectionItem(nil, kind: .folder)], .convert, .foldersCannotConvert),
        ([SelectionItem(.png, isLocal: false)], .convert, .inaccessible),
        ([SelectionItem(nil)], .convert, .unsupportedFile),
        ([SelectionItem(.ogg)], .tools, .noTools(.ogg)),
        ([SelectionItem(.jpg), SelectionItem(.mp4)], .tools, .noTools(nil)),
        ([SelectionItem(nil, kind: .folder)], .tools, .noTools(nil)),
        ([SelectionItem(.jpg, isLocal: false)], .tools, .inaccessible),
        ([SelectionItem(.jpg, isLocal: false)], .actions, .onlyLocalItems),
    ])
    func emptyStates(items: [SelectionItem], mode: WheelMode, reason: EmptyReason) {
        #expect(builder.content(for: mode, items: items) == .empty(reason))
    }

    @Test func packagesConvertLikeFiles() {
        let content = builder.content(for: .convert, items: [SelectionItem(.pages, kind: .package)])
        #expect(targets(content).first == .convert(.docx))
    }

    @Test func capabilityGateHidesTargetsAndExplainsWhenNothingIsLeft() {
        let noWebM = CapabilitySnapshot(unavailableTargets: [.webm])
        #expect(
            !targets(builder.content(for: .convert, items: files(.mp4), capabilities: noWebM)).contains(.convert(.webm))
        )
        let noArchives = CapabilitySnapshot(unavailableTargets: [.tar, .gz])
        #expect(
            builder.content(for: .convert, items: files(.zip), capabilities: noArchives)
                == .empty(.noInstalledConverter(.zip)))
    }

    @Test func toolsUseTheTotalItemCount() {
        let one = builder.content(for: .tools, items: files(.mp4))
        let two = builder.content(for: .tools, items: files(.mp4, .mov))
        #expect(one.slices.count == 9)
        #expect(targets(two) == [.shrink, .stripMetadata, .videoMute, .videoJoin].map(SliceTarget.tool))
        #expect(two.slices.first?.symbolName != nil)
    }

    @Test func actionsAreAlwaysTheSixIncludingFolders() {
        let items = [SelectionItem(nil, kind: .folder), SelectionItem(.xlsx), SelectionItem(nil)]
        let content = builder.content(for: .actions, items: items)
        #expect(targets(content) == ActionID.allCases.map(SliceTarget.action))
    }

    @Test func emptyStateCopy() {
        #expect(builder.message(for: .noInstalledConverter(.gz)) == "GZIP needs an engine that isn't installed")
        #expect(builder.message(for: .noTools(.ogg)) == "No tools for OGG files")
        #expect(builder.message(for: .noTools(nil)) == "No tools for these items")
        #expect(builder.message(for: .foldersCannotConvert) == "Folders work with Actions only")
    }

    @Test func acceptedModesFeedTheTrigger() {
        #expect(builder.acceptedModes(items: files(.ogg)) == [.convert, .actions])
        #expect(builder.acceptedModes(items: [SelectionItem(nil, kind: .folder)]) == [.actions])
        #expect(builder.acceptedModes(items: files(.png)) == Set(WheelMode.allCases))
    }
}
```

#### 7c.2 Run, expect failure

`swift test --filter ZivletWheelCoreTests` → `error: cannot find 'SelectionItem' in scope` (and `SliceBuilder`,
`WheelContent`, `EmptyReason`, `CapabilitySnapshot`).

#### 7c.3 Implement

`WheelContent.swift` (complete; the copy strings are Zivlet's own, 01-prd §5.10) [critic3: strings rewritten, re-verified 24/24 green and lint clean]:

```swift
import ZivletCore

public enum SelectionItemKind: String, Sendable, Codable { case file, folder, package }

/// One dragged item as seen by the slice builder. `format == nil` = unknown type.
public struct SelectionItem: Sendable, Equatable, Codable {
    public let format: FormatID?
    public let kind: SelectionItemKind
    public let isLocal: Bool
    public init(_ format: FormatID?, kind: SelectionItemKind = .file, isLocal: Bool = true) {
        self.format = format
        self.kind = kind
        self.isLocal = isLocal
    }
}

public enum SliceTarget: Sendable, Hashable, Codable {
    case convert(FormatID), tool(ToolID), action(ActionID)
}

public struct WheelSlice: Sendable, Equatable, Identifiable {
    public let id: String  // stable per mode → glass morph identity
    public let label: String
    public let symbolName: String?
    public let target: SliceTarget
    public let badge: String?  // "1 of 3" for mixed-family conversions
}

/// Empty-state copy is Zivlet's own (03a §2.6, 01-prd §5.10).
public enum EmptyReason: Sendable, Equatable {
    case noItems, inaccessible, onlyLocalItems, foldersCannotConvert, unsupportedFile
    case noCommonFormat, noInstalledConverter(FormatID), noTools(FormatID?)

    // [review] Was `var message` reading FormatRegistry.standard; now the caller's registry is injected:
    // `message(using:)`, and `SliceBuilder.message(for:)` passes the builder's registry.
    public func message(using registry: FormatRegistry) -> String {
        switch self {
        case .noItems: "Nothing to work on yet"
        case .inaccessible: "Zivlet can't read one of these files"
        case .onlyLocalItems: "Actions work on items stored on this Mac"
        case .foldersCannotConvert: "Folders work with Actions only"
        case .unsupportedFile: "Zivlet doesn't know this file type"
        case .noCommonFormat: "These files can't share a format"
        case .noInstalledConverter(let f): "\(Self.label(f)) needs an engine that isn't installed"
        case .noTools(let f?): "No tools for \(Self.label(f)) files"
        case .noTools(nil): "No tools for these items"
        }
    }

    private static func label(_ format: FormatID) -> String { FormatRegistry.standard.format(format).wheelLabel }
}

public enum WheelContent: Sendable, Equatable {
    case slices([WheelSlice])
    case empty(EmptyReason)

    public var slices: [WheelSlice] {
        if case .slices(let s) = self { return s }
        return []
    }
}

/// Minimal capability gate (03a §3.5): targets whose engine is missing are hidden.
public struct CapabilitySnapshot: Sendable, Equatable, Codable {
    public static let full = CapabilitySnapshot(unavailableTargets: [])
    public let unavailableTargets: Set<FormatID>
    public init(unavailableTargets: Set<FormatID>) { self.unavailableTargets = unavailableTargets }
}
```

`SliceBuilder.swift` — outline:

```swift
public struct SliceBuilder: Sendable {
    public init(conversions: ConversionCatalog = .standard, tools: ToolCatalog = .standard,
                registry: FormatRegistry = .standard, maxSlots: Int = WheelGeometry.standard.maxSlots)
    public func content(for mode: WheelMode, items: [SelectionItem],
                        capabilities: CapabilitySnapshot = .full) -> WheelContent   // empty items → .noItems, then per mode
    public func acceptedModes(items: [SelectionItem], capabilities: CapabilitySnapshot = .full) -> Set<WheelMode>
    // private toolContent(_:) and actionContent(_:) implement the tools/actions rows above.
    // Slice ids are "<mode>.<rawValue>" (for example "tools.shrink"), stable for the glass morph.
}
```

`SliceBuilder+Convert.swift` (complete; the mixed-family branch is the Zivlet addition):

```swift
import ZivletCore

// Conversion slices: one format, same family (shared targets), or mixed families (badged union).
extension SliceBuilder {
    func convertContent(_ items: [SelectionItem], _ caps: CapabilitySnapshot) -> WheelContent {
        guard items.allSatisfy(\.isLocal) else { return .empty(.inaccessible) }
        if items.contains(where: { $0.kind == .folder }) { return .empty(.foldersCannotConvert) }
        let formats = items.compactMap(\.format)
        guard formats.count == items.count else { return .empty(.unsupportedFile) }
        let distinct = formats.uniqued()
        let families = distinct.map { registry.format($0).family }.uniqued()
        if families.count == 1 { return sameFamily(distinct, caps) }
        return mixedFamilies(formats, families: families, caps)
    }

    /// First format's targets that every other format can also produce, in that order (03a §2.6).
    private func sameFamily(_ formats: [FormatID], _ caps: CapabilitySnapshot) -> WheelContent {
        let shared = sharedTargets(formats)
        let available = shared.filter { !caps.unavailableTargets.contains($0) }
        if !available.isEmpty { return .slices(available.map { slice($0, badge: nil) }) }
        if formats.count == 1, !shared.isEmpty { return .empty(.noInstalledConverter(formats[0])) }
        return .empty(formats.count == 1 ? .unsupportedFile : .noCommonFormat)
    }

    /// Zivlet addition (03a §2.6, 06 P0-8): union grouped by family, badged "k of n", only if ≤ 12 slots.
    private func mixedFamilies(
        _ formats: [FormatID], families: [FormatFamily],
        _ caps: CapabilitySnapshot
    ) -> WheelContent {
        let ordered = families.flatMap { family in
            sharedTargets(formats.uniqued().filter { registry.format($0).family == family })
        }.uniqued().filter { !caps.unavailableTargets.contains($0) }
        guard !ordered.isEmpty, ordered.count <= maxSlots else { return .empty(.noCommonFormat) }
        return .slices(
            ordered.map { target in
                let able = formats.filter { conversions.canConvert($0, to: target) }.count
                return slice(target, badge: able < formats.count ? "\(able) of \(formats.count)" : nil)
            })
    }

    private func sharedTargets(_ formats: [FormatID]) -> [FormatID] {
        guard let first = formats.first else { return [] }
        return conversions.targets(for: first).filter { target in
            formats.dropFirst().allSatisfy { conversions.canConvert($0, to: target) }
        }
    }

    private func slice(_ target: FormatID, badge: String?) -> WheelSlice {
        WheelSlice(
            id: "convert.\(target.rawValue)", label: registry.format(target).wheelLabel, symbolName: nil,
            target: .convert(target), badge: badge)
    }
}
```

#### 7c.4 Verify green

`swift test --filter ZivletWheelCoreTests` → `✔ Test run with 24 tests in 3 suites passed`.

#### 7c.5 Commit

```bash
git add Packages/ZivletKit
git commit -s -m "feat(wheel): derive slice lists per mode with mixed-selection and empty-state rules"
```

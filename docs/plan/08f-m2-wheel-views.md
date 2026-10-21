# 08f — M2 task 9: petal shapes and the Glass/Solid wheel views

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 9 — `PetalShape`, `RingShape` and `WheelView` (P0-42)

| Field | Value |
|---|---|
| Goal | SwiftUI drawing of the wheel from WheelCore's polar maths. Petals: annular sectors r 48.64…119.52 with a constant 4 pt gap and rounded corners, highlight growth 1.05 built into the path. Glass theme: the backdrop disk as `.clear` glass, a glass hub disc, and the petals in one `GlassEffectContainer(spacing: 6)` with `glassEffectID` and `.matchedGeometry` for the mode morph; the hot petal gets the accent gradient plus `.tint`. Solid theme: opaque greys and the same accent gradient. Labels: 12 pt semibold formats, 12.6 pt symbol + 7.5 pt label for tools and actions, "k of n" badges. Hub label, status pill (276 × 58, corner 15), reject shake, intro (scale 0.45 → 1 over 0.20 s, curve 0.18/0.82/0.24/1.0), highlight `.snappy(0.12)`, morph `.spring(0.28, bounce 0.15)`, Reduce Motion → 80 ms fades |
| 05 rows | P0-42 (render tests replace PNG goldens, index §2.1) |
| Sources | 03a §2.2 (geometry, labels, pill), 03a §2.3 (slot order), 03a §2.7 (animation, glass, Reduce Motion/Transparency), 14 §2.3 (`PetalShape`, glass APIs, `.interactive` not used during a drag), 05 P0-42, index D-M2-6, D-M2-7 |

Outline of one petal (n ≥ 2), with AppKit angles (y up). `s` and `e` are the counter-clockwise and clockwise edges of
the slot's sector; `ε(r) = asin(min(2/r, 0.95))` is the gap inset at radius r:

```text
start on edge s at r = inner + 8 → line along edge s to r = outer − 20.16
→ quad curve to the outer arc (control: the sharp corner at r = outer), arc inset min(0.24·span, 0.15)
→ outer arc clockwise → quad curve back to edge e at r = outer − 20.16 → line along edge e to r = inner + 8
→ quad curve to the inner arc (inset min(0.18·span, 0.18)) → inner arc counter-clockwise → quad curve → close
```

Points on edge s at radius r have angle `s − ε(r)`, so they lie on a line 2 pt from the slot boundary: the straight
segments keep the 4 pt gap exact. SwiftUI's y-down frame is handled in one place (`WheelLayout.point`), and arcs use
`addRelativeArc` with signed deltas, so arc direction never depends on the flipped `clockwise` flag.

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletWheel/PetalShape.swift` (`WheelLayout`, `RingShape`, `PetalShape`) |
| create | `Sources/ZivletWheel/WheelParts.swift` (`PetalLabel`, `HubLabelView`, `StatusPill`, `ShakeEffect`) |
| create | `Sources/ZivletWheel/WheelView.swift` |
| create | `Tests/ZivletWheelTests/WheelViewTests.swift` |

### 9.1 Failing tests first

Shape tests use `Path.contains`. Render tests use `ImageRenderer` at scale 1 and read pixels. Off-screen glass output
is not representative (04 §6.6), so Glass renders are checked for success only, and colour is asserted on the Solid
theme. Glass was judged on screen through the Task 11 demo screenshots.

`Packages/ZivletKit/Tests/ZivletWheelTests/WheelViewTests.swift`:

```swift
import AppKit
import ZivletCore
import ZivletWheelCore
import SwiftUI
import Testing

@testable import ZivletWheel

@Suite("Petal shapes and wheel rendering (P0-42, 03a §2.2)")
struct WheelViewTests {
    let geometry = WheelGeometry.standard
    let rect = CGRect(x: 0, y: 0, width: 372, height: 372)

    /// AppKit polar (y up) → SwiftUI point in the 372 pt frame (y down).
    func point(_ r: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: 186 + r * cos(angle), y: 186 - r * sin(angle))
    }

    @Test(arguments: 2...12)
    func petalCoversItsLabelButNotTheGapHubOrRim(count: Int) {
        let span = 2 * Double.pi / Double(count)
        for slot in 0..<count {
            let path = PetalShape(slot: slot, count: count).path(in: rect)
            let centre = geometry.centreAngle(slot: slot, count: count)
            #expect(path.contains(point(geometry.labelRadius, centre)))
            #expect(path.contains(point(110, centre)) && path.contains(point(55, centre)))
            #expect(!path.contains(point(84, centre + span / 2)))
            #expect(!path.contains(point(30, centre)) && !path.contains(point(122, centre)))
        }
    }

    /// The 1.05 highlight lives in the path (scaled about the wheel centre): `scaleEffect` on a view inside a
    /// `GlassEffectContainer` moved the glass off its petal in the M2 prototype.
    @Test func highlightGrowsThePetalOutwardAroundTheCentre() {
        let centre = geometry.centreAngle(slot: 0, count: 6)
        let grown = PetalShape(slot: 0, count: 6, grow: 1.05).path(in: rect)
        #expect(grown.contains(point(123, centre)) && !grown.contains(point(49.5, centre)))
        #expect(!PetalShape(slot: 0, count: 6).path(in: rect).contains(point(123, centre)))
        var shape = PetalShape(slot: 0, count: 6)
        shape.animatableData = 1.05
        #expect(shape.grow == 1.05)
    }

    @Test func petalsStayInsideTheOuterRadius() {
        for count in 1...12 {
            let bounds = PetalShape(slot: 0, count: count).path(in: rect).boundingRect
            let corners = [bounds.origin, CGPoint(x: bounds.maxX, y: bounds.maxY)]
            #expect(corners.allSatisfy { abs($0.x - 186) <= 119.6 && abs($0.y - 186) <= 119.6 })
        }
    }

    @Test func singleSlotIsAFullRingWithAHole() {
        let ring = PetalShape(slot: 0, count: 1).path(in: rect)
        #expect(ring.contains(point(84, 0)) && ring.contains(point(84, 2)))
        #expect(!ring.contains(CGPoint(x: 186, y: 186)))
        let disk = RingShape(inner: geometry.hubRadius, outer: geometry.ringOuter).path(in: rect)
        #expect(disk.contains(point(124, 1)) && !disk.contains(point(40, 1)) && !disk.contains(point(127, 1)))
    }

    @Test func labelPointsMatchWheelCore() {
        let label = WheelLayout.labelPoint(slot: 0, count: 6)
        #expect(abs(label.x - 186) < 1e-9 && abs(label.y - (186 - geometry.labelRadius)) < 1e-9)
    }

    /// Solid theme pixels: idle petals are dark grey, the highlighted petal takes the accent.
    @Test func solidThemeTintsOnlyTheHighlightedPetal() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.slices(6, highlighted: 0), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        let image = try #require(render(store))
        #expect(image.width == 372 && image.height == 372)
        let hot = try #require(pixel(image, at: point(100, Double.pi / 2)))
        let idle = try #require(pixel(image, at: point(100, -Double.pi / 2)))
        #expect(hot.blue > hot.red + 0.2)
        #expect(abs(idle.red - idle.blue) < 0.05 && idle.red < 0.35)
    }

    /// The hub is a disc, not a hole, so the label never sits on whatever is behind the panel.
    @Test func solidHubIsAnOpaqueDisc() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.slices(6), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        let image = try #require(render(store))
        let hub = try #require(pixel(image, at: point(30, 0.3)))
        #expect(hub.alpha > 0.99 && hub.red < 0.15)
        let outside = try #require(pixel(image, at: point(160, 0.3)))
        #expect(outside.alpha < 0.01)
    }

    @Test(arguments: 1...9)
    func everySlotCountRendersInBothThemes(count: Int) throws {
        for theme in WheelTheme.allCases {
            let store = WheelStore(feedback: FakeFeedback())
            let appearance = WheelAppearance(theme: theme, palette: Fixtures.appearance.palette, reduceMotion: false)
            store.present(Fixtures.slices(count, highlighted: count - 1), emptyMessage: nil, appearance: appearance)
            store.expand()
            #expect(render(store) != nil)
        }
    }

    @Test func toolLabelsAndEmptyPillRender() throws {
        let store = WheelStore(feedback: FakeFeedback())
        store.present(Fixtures.model(.tools, [.mov]), emptyMessage: nil, appearance: Fixtures.appearance)
        store.expand()
        #expect(render(store) != nil)
        let empty = WheelModel(mode: .tools, content: .empty(.noTools(.srt)), idleHubLabel: "a.srt")
        store.present(empty, emptyMessage: "No tools for SRT files", appearance: Fixtures.appearance)
        #expect(render(store) != nil)
        store.dismiss()
        #expect(render(store) != nil)
    }

    func render(_ store: WheelStore) -> CGImage? {
        let renderer = ImageRenderer(content: WheelView(store: store).environment(\.colorScheme, .dark))
        renderer.scale = 1
        return renderer.cgImage
    }

    func pixel(_ image: CGImage, at p: CGPoint) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var data = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: -p.x, y: p.y - Double(image.height) + 1, width: 372, height: 372))
        return (Double(data[0]) / 255, Double(data[1]) / 255, Double(data[2]) / 255, Double(data[3]) / 255)
    }
}
```

### 9.2 Run, expect failure

`swift test --filter ZivletWheelTests` → `error: cannot find 'PetalShape' in scope` (also `RingShape`,
`WheelLayout`, `WheelView`).

### 9.3 Implement (complete)

Shapes are `nonisolated`: `Shape.path(in:)` is a nonisolated requirement, and a main-actor conformance fails with
`conformance of 'PetalShape' to protocol 'Shape' crosses into main actor-isolated code`.

`Packages/ZivletKit/Sources/ZivletWheel/PetalShape.swift`:

```swift
import ZivletWheelCore
import SwiftUI

/// Maps WheelCore's polar maths (AppKit, y up) into the 372 pt SwiftUI frame (y down).
nonisolated enum WheelLayout {
    static let geometry = WheelGeometry.standard
    static let centre = CGPoint(x: geometry.panelSide / 2, y: geometry.panelSide / 2)

    static func point(radius: Double, angle: Double, in rect: CGRect? = nil) -> CGPoint {
        let c = rect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? centre
        return CGPoint(x: c.x + radius * cos(angle), y: c.y - radius * sin(angle))
    }

    static func labelPoint(slot: Int, count: Int) -> CGPoint {
        point(radius: geometry.labelRadius, angle: geometry.centreAngle(slot: slot, count: count))
    }
}

/// Annulus; also the single-slot petal and the backdrop disk.
nonisolated struct RingShape: Shape {
    let inner: Double
    let outer: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addRelativeArc(center: c, radius: outer, startAngle: .zero, delta: .radians(2 * .pi))
        path.closeSubpath()
        path.addRelativeArc(center: c, radius: inner, startAngle: .zero, delta: .radians(-2 * .pi))
        path.closeSubpath()
        return path
    }
}

/// One petal (03a §2.2): annular sector from r 48.64 to 119.52 with a constant 4 pt gap to its neighbours and
/// rounded corners. Outer corners start 20.16 pt inside the rim with angular inset min(0.24·span, 0.15); inner
/// corners rise 8 pt [new] with inset min(0.18·span, 0.18). The curve itself is Zivlet's own construction.
/// `grow` (1.05 when highlighted) scales the outline about the wheel centre, so the petal grows outward and the
/// glass stays on its petal. It is the only `var`: SwiftUI animates it through `animatableData`.
nonisolated struct PetalShape: Shape {
    static let innerCornerRise = 8.0
    let slot: Int
    let count: Int
    var grow = 1.0
    let geometry = WheelGeometry.standard

    init(slot: Int, count: Int, grow: Double = 1) {
        self.slot = slot
        self.count = count
        self.grow = grow
    }

    var animatableData: Double {
        get { grow }
        set { grow = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outline = outline(in: rect)
        guard grow != 1 else { return outline }
        let scale = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: grow, y: grow)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return outline.applying(scale)
    }

    private func outline(in rect: CGRect) -> Path {
        let g = geometry
        guard count > 1 else { return RingShape(inner: g.petalInner, outer: g.petalOuter).path(in: rect) }
        let span = g.span(count: count)
        let start = g.centreAngle(slot: slot, count: count) + span / 2  // counter-clockwise edge
        let end = start - span  // clockwise edge
        let (outerInset, innerInset) = g.cornerInsets(count: count)
        let rimCorner = g.petalOuter - g.outerCornerInset
        let hubCorner = g.petalInner + Self.innerCornerRise
        func p(_ r: Double, _ a: Double) -> CGPoint { WheelLayout.point(radius: r, angle: a, in: rect) }
        func e(_ r: Double) -> Double { g.edgeInset(atRadius: r) }
        let outerFrom = start - e(g.petalOuter) - outerInset
        let outerTo = end + e(g.petalOuter) + outerInset
        let innerFrom = end + e(g.petalInner) + innerInset
        let innerTo = start - e(g.petalInner) - innerInset
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: p(hubCorner, start - e(hubCorner)))
        path.addLine(to: p(rimCorner, start - e(rimCorner)))
        path.addQuadCurve(to: p(g.petalOuter, outerFrom), control: p(g.petalOuter, start - e(g.petalOuter)))
        path.addRelativeArc(
            center: c, radius: g.petalOuter, startAngle: .radians(-outerFrom), delta: .radians(outerFrom - outerTo))
        path.addQuadCurve(to: p(rimCorner, end + e(rimCorner)), control: p(g.petalOuter, end + e(g.petalOuter)))
        path.addLine(to: p(hubCorner, end + e(hubCorner)))
        path.addQuadCurve(to: p(g.petalInner, innerFrom), control: p(g.petalInner, end + e(g.petalInner)))
        path.addRelativeArc(
            center: c, radius: g.petalInner, startAngle: .radians(-innerFrom), delta: .radians(innerFrom - innerTo))
        path.addQuadCurve(to: p(hubCorner, start - e(hubCorner)), control: p(g.petalInner, start - e(g.petalInner)))
        path.closeSubpath()
        return path
    }
}
```

`Packages/ZivletKit/Sources/ZivletWheel/WheelParts.swift`:

```swift
import ZivletWheelCore
import SwiftUI

/// Format label (12 pt semibold) or symbol + tool/action label (12.6 pt symbol, 7.5 pt text) (03a §2.2).
struct PetalLabel: View {
    let slice: WheelSlice
    let position: CGPoint
    let colour: Color

    var body: some View {
        content
            .foregroundStyle(colour)
            .multilineTextAlignment(.center)
            .position(position)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        if let symbol = slice.symbolName {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 12.6, weight: .medium))
                Text(slice.label).font(.system(size: 7.5, weight: .semibold)).tracking(0.2)
                    .lineLimit(2).frame(width: 82, height: 22, alignment: .top)
            }
        } else {
            VStack(spacing: 0) {
                Text(slice.label).font(.system(size: 12, weight: .semibold)).tracking(0.35).frame(width: 82, height: 24)
                if let badge = slice.badge { Text(badge).font(.system(size: 7, weight: .medium)).opacity(0.8) }
            }
        }
    }
}

/// Hub text: 10 pt medium for one item, 7 pt semibold for several, shrinking to fit 58 × 28 (03a §2.2).
struct HubLabelView: View {
    let text: String
    let compact: Bool
    let colour: Color

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 7 : 10, weight: compact ? .semibold : .medium))
            .tracking(0.2)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.55)
            .foregroundStyle(colour)
            .frame(width: 58, height: 28)
    }
}

/// Empty-state or reject message: 276 × 58, corner 15, 14 pt medium, two lines (03a §2.2).
struct StatusPill: View {
    let text: String
    let theme: WheelTheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .frame(width: 276, height: 58)
            .background {
                if theme == .solid { shape.fill(Color(white: 0.12)) }
            }
            .foregroundStyle(theme == .solid ? Color.white : Color.primary)
            .glassEffect(theme == .glass ? .regular : .identity, in: shape)
    }
}

/// Horizontal three-cycle shake for a refused wheel switch (03a §2.7).
nonisolated struct ShakeEffect: GeometryEffect {
    var travel: Double = 6
    var shakes: Double = 3
    var animatableData: Double

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 2 * shakes), y: 0))
    }
}
```

Glass details settled with prototype screenshots (index D-M2-6, D-M2-7): petals stay distinct at container spacing 6;
the disk glass sits outside the container so it never blends with the petals (a design choice); the hot petal's 1.05 growth is
`PetalShape.grow`, not `scaleEffect` (which moved the glass off the petal); the hub is a disc.

`Packages/ZivletKit/Sources/ZivletWheel/WheelView.swift`:

```swift
import ZivletWheelCore
import SwiftUI

/// The wheel: backdrop disk, petals (Liquid Glass or Solid), hub label and status pill. Highlight is model-driven
/// because hover never reaches us during an external drag (14 §2.3).
public struct WheelView: View {
    let store: WheelStore
    @Namespace private var glassSpace

    public init(store: WheelStore) { self.store = store }

    public var body: some View {
        ZStack {
            if let model = store.model {
                petals(model)
                    .scaleEffect(store.isExpanded || store.appearance.reduceMotion ? 1 : WheelTiming.introScale)
                    .opacity(store.isExpanded ? 1 : 0)
                    .modifier(ShakeEffect(animatableData: Double(store.rejectCount)))
                HubLabelView(text: model.hubLabel, compact: model.hubIsCompact, colour: hubColour)
                if let text = store.pillText { StatusPill(text: text, theme: store.theme) }
            }
        }
        .frame(width: WheelLayout.geometry.panelSide, height: WheelLayout.geometry.panelSide)
        .animation(introAnimation, value: store.isExpanded)
        .animation(motion(.snappy(duration: WheelTiming.highlight)), value: store.model?.highlighted)
        .animation(
            motion(.spring(duration: WheelTiming.morph, bounce: WheelTiming.morphBounce)), value: store.model?.mode
        )
        .animation(.linear(duration: WheelTiming.shake), value: store.rejectCount)
    }

    @ViewBuilder private func petals(_ model: WheelModel) -> some View {
        let g = WheelLayout.geometry
        let disk = RingShape(inner: g.hubRadius, outer: g.ringOuter)
        // The hub is a r 42.24 disc, so its label never sits on whatever is behind the panel.
        let hub = Circle().inset(by: g.panelSide / 2 - g.hubRadius)
        switch store.theme {
        case .glass:
            ZStack {
                Color.clear.glassEffect(.clear, in: disk)
                Color.clear.glassEffect(.regular, in: hub)
                GlassEffectContainer(spacing: 6) {
                    ZStack { ForEach(Array(model.slices.enumerated()), id: \.element.id) { glassPetal($1, $0, model) } }
                }
            }
        case .solid:
            ZStack {
                disk.fill(Color(white: 0.08))
                hub.fill(Color(white: 0.08))
                ForEach(Array(model.slices.enumerated()), id: \.element.id) { solidPetal($1, $0, model) }
            }
        }
    }

    private func glassPetal(_ slice: WheelSlice, _ index: Int, _ model: WheelModel) -> some View {
        let hot = model.highlighted == index
        let shape = PetalShape(slot: index, count: model.slices.count, grow: hot ? 1.05 : 1)
        let palette = store.appearance.palette
        return label(slice, index, model, colour: hot ? palette.labelOnAccent.color : .primary)
            .background { if hot { shape.fill(accentGradient).opacity(0.9) } }
            .glassEffect(hot ? .regular.tint(palette.base.color) : .regular, in: shape)
            .glassEffectID(slice.id, in: glassSpace)
            .glassEffectTransition(.matchedGeometry)
    }

    private func solidPetal(_ slice: WheelSlice, _ index: Int, _ model: WheelModel) -> some View {
        let hot = model.highlighted == index
        let shape = PetalShape(slot: index, count: model.slices.count)
        return ZStack {
            if hot { shape.fill(accentGradient) } else { shape.fill(Color(white: 0.18)) }
            label(
                slice, index, model, colour: hot ? store.appearance.palette.labelOnAccent.color : .white.opacity(0.96))
        }
        .scaleEffect(hot ? 1.05 : 1)
    }

    /// Highlight fill from the one accent token: light → base → dark from the petal's inner to outer radius.
    private var accentGradient: RadialGradient {
        let palette = store.appearance.palette
        return RadialGradient(
            stops: [
                .init(color: palette.light.color, location: 0.2), .init(color: palette.base.color, location: 0.56),
                .init(color: palette.dark.color, location: 1),
            ], center: .center, startRadius: WheelLayout.geometry.petalInner,
            endRadius: WheelLayout.geometry.petalOuter)
    }

    private func label(_ slice: WheelSlice, _ index: Int, _ model: WheelModel, colour: Color) -> some View {
        PetalLabel(
            slice: slice, position: WheelLayout.labelPoint(slot: index, count: model.slices.count), colour: colour
        )
        .frame(width: WheelLayout.geometry.panelSide, height: WheelLayout.geometry.panelSide)
        .opacity(store.isExpanded ? 1 : 0)
    }

    private var hubColour: Color { store.theme == .solid ? .white : .primary }

    private var introAnimation: Animation {
        store.appearance.reduceMotion
            ? .easeOut(duration: WheelTiming.reducedMotionFade)
            : .timingCurve(0.18, 0.82, 0.24, 1.0, duration: WheelTiming.intro)
    }

    /// Reduce Motion turns springs into short fades (03a §2.7).
    private func motion(_ animation: Animation) -> Animation {
        store.appearance.reduceMotion ? .easeOut(duration: WheelTiming.reducedMotionFade) : animation
    }
}
```

### 9.4 Verify green

`swift test --filter ZivletWheelTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 38 tests in 5 suites passed`.

### 9.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletWheel Packages/ZivletKit/Tests/ZivletWheelTests
git commit -s -m "feat(wheel): add petal shapes and Glass/Solid SwiftUI wheel views"
```

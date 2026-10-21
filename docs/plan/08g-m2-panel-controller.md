# 08g — M2 task 10: WheelPanel, WheelDropView, WheelController

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 10 — The overlay panel, the AppKit drop target and the controller (P0-41)

| Field | Value |
|---|---|
| Goal | `WheelPanel`: borderless, non-activating `NSPanel`, level `.popUpMenu` (101), collection behaviour `0x159` (all Spaces, full-screen auxiliary, transient, stationary, ignores cycle), clear and shadowless, never key or main, **ignores the mouse while hidden**, 372 pt. `WheelDropView`: the content view and the only drag destination (`.fileURL`); the `NSHostingView` inside has no drop modifiers. `WheelController`: pre-warms at launch, executes `show`/`switchTo`/`reject`/`hide`, places the panel with `PanelPlacer`, hit-tests each `draggingUpdated` through `WheelModel.hit`, negotiates the operation, re-reads URLs at drop and requires them to equal the probed set, then hands a `WheelSelection` to its delegate |
| 05 rows | P0-41 (03a §1.5 150 ms release timeout, per 06 D3) |
| Sources | 03a §2.1 (panel table), 03a §2.5 (drop protocol), 14 §2.1 (panel code, pre-warm), 14 §2.2 (drop target during an external drag), 02 §8 (≤ 1 ms `performDragOperation`) |

| Callback (`WheelDropView`) | Controller | Result |
|---|---|---|
| `draggingEntered` | `dragEntered(at:offered:)` | pointer inside = true (feeds `InputSample.pointerInsideWheel`), then as updated |
| `draggingUpdated` | `dragUpdated(at:offered:)` | `store.pointer(hit)`; `DropNegotiation` → copy / generic / link / move or `[]` |
| `draggingExited` | `dragExited()` | pointer inside = false, highlight cleared |
| `prepareForDragOperation` | `canAcceptDrop()` | true only with a highlighted slice (hub → false → Finder snaps back) |
| `performDragOperation` | `performDrop(from:)` | URLs must equal the payload, else false + error log; delegate gets the selection; returns at once |
| `draggingEnded` | `dragEnded()` | pointer inside = false; `onDragEnded` → trigger `.dropHandled` (T16) |

Show: placement → `store.present` (collapsed) → `setFrame` → `ignoresMouseEvents = false` → alpha 0 →
`orderFrontRegardless` → 70 ms ease-out fade. The view's `.task(id: store.presentation)` then calls
`store.expandIfPending`, after the update that rendered the collapsed wheel, so the 0.45 → 1 intro never coalesces;
`hide()` calls `store.cancelExpansion()` first. Hide: 80 ms fade, then `orderOut` and reset. A show during the fade wins (a generation counter).

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletWheel/WheelPanel.swift` (`WheelPanel`, `WheelDropHandling`, `WheelDropView`) |
| create | `Sources/ZivletWheel/WheelController.swift` (`WheelControllerDelegate`, `WheelController`, `Rect2D` ↔ `CGRect`) |
| create | `Sources/ZivletWheel/WheelController+Drop.swift` |
| create | `Tests/ZivletWheelTests/WheelControllerTests.swift` |

### 10.1 Failing tests first

The rig gives the controller a fake 1440 × 900 screen, a private pasteboard and the fake feedback. The drop-protocol
methods are called directly with view points, because `NSDraggingInfo` cannot be built without a real drag. The drag
`override`s in `WheelDropView` are one-line forwards, so the real drag path is covered by QA rows Q1–Q6. AppKit rounds
window frames to whole points, so frame assertions allow 1 pt (index D-M2-13).

`Packages/ZivletKit/Tests/ZivletWheelTests/WheelControllerTests.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger
import ZivletWheelCore
import Testing

@testable import ZivletWheel

final class SelectionLog: WheelControllerDelegate {
    private(set) var selections: [WheelSelection] = []
    func wheelController(_ controller: WheelController, didSelect selection: WheelSelection) {
        selections.append(selection)
    }
}

/// A controller on a fake 1440 × 900 screen, fed from a private pasteboard.
@MainActor
final class WheelRig {
    static let screen = ScreenFrame(
        frame: Rect2D(x: 0, y: 0, width: 1440, height: 900), visibleFrame: Rect2D(x: 0, y: 0, width: 1440, height: 875))
    let pasteboard = NSPasteboard.withUniqueName()
    let feedback = FakeFeedback()
    let log = SelectionLog()
    let reader: DragPayloadReader
    let controller: WheelController
    private(set) var dragEnds = 0

    init() {
        reader = DragPayloadReader(pasteboard: pasteboard)
        controller = WheelController(
            reader: reader, feedback: feedback, screens: { [WheelRig.screen] },
            appearance: { Fixtures.appearance })
        controller.delegate = log
        controller.onDragEnded = { [unowned self] in dragEnds += 1 }
    }

    /// Puts files on the pasteboard and runs the payload probe, as the trigger host would.
    func drag(_ urls: [URL]) async {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        _ = await reader.summary(changeCount: pasteboard.changeCount)
    }

    /// View point (y up, origin bottom-left of the 372 pt panel) at polar (r, angle) around the centre.
    func viewPoint(_ r: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: 186 + r * cos(angle), y: 186 + r * sin(angle))
    }
}

@Suite("Wheel panel, drop view and controller (P0-41, 03a §2.1, §2.5)", .serialized)
@MainActor
struct WheelControllerTests {
    @Test func panelIsANonActivatingAllSpacesOverlay() {
        let panel = WheelPanel()
        #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
        #expect(panel.level == .popUpMenu && panel.collectionBehavior.rawValue == 0x159)
        #expect(!panel.isOpaque && panel.backgroundColor == .clear && !panel.hasShadow)
        #expect(!panel.hidesOnDeactivate && panel.animationBehavior == .none && !panel.isMovable)
        #expect(!panel.canBecomeKey && !panel.canBecomeMain && panel.ignoresMouseEvents)
        #expect(panel.frame.size == CGSize(width: 372, height: 372))
    }

    @Test func dropViewIsTheContentViewAndAcceptsFileURLs() {
        let controller = WheelRig().controller
        let view = controller.panel.contentView as? WheelDropView
        #expect(view?.registeredDraggedTypes.contains(.fileURL) == true)
        #expect(view?.subviews.count == 1)
    }

    @Test func prewarmLeavesTheWheelHidden() async {
        let rig = WheelRig()
        await rig.controller.prewarm()
        #expect(!rig.controller.panel.isVisible && rig.controller.store.model == nil)
    }

    @Test func showPlacesThePanelOnThePointerWithTheModeSlices() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        let panel = rig.controller.panel
        #expect(panel.isVisible && !panel.ignoresMouseEvents)
        #expect(panel.frame == CGRect(x: 514, y: 214, width: 372, height: 372))
        #expect(rig.controller.store.model?.slices.first?.target == .convert(.jpg))
        #expect(rig.controller.store.model?.idleHubLabel == "a.png\n1.2 KB")
        rig.controller.hide()
    }

    @Test func showNearACornerKeepsTheDiskOnScreen() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.actions, at: Point2D(x: 2, y: 2)))
        // AppKit rounds window frames to whole points.
        let origin = rig.controller.panel.frame.origin
        #expect(abs(origin.x - (133.92 - 186)) <= 1 && abs(origin.y - (133.92 - 186)) <= 1)
        rig.controller.hide()
    }

    @Test func showWithoutAPayloadDoesNothing() {
        let rig = WheelRig()
        rig.controller.apply(.show(.convert, at: .zero))
        #expect(!rig.controller.panel.isVisible)
    }

    @Test func draggingHighlightsSlotsAndNegotiatesCopy() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        let entered = rig.controller.dragEntered(at: rig.viewPoint(90, .pi / 2), offered: [.move, .copy])
        #expect(entered == .copy && rig.controller.isPointerInside)
        #expect(rig.controller.store.model?.highlighted == 0 && rig.controller.canAcceptDrop())
        #expect(rig.controller.dragUpdated(at: rig.viewPoint(10, 0), offered: [.move]) == [])
        #expect(rig.controller.store.model?.highlighted == nil && !rig.controller.canAcceptDrop())
        #expect(rig.feedback.events == ["highlight"])
        rig.controller.dragExited()
        #expect(!rig.controller.isPointerInside)
        rig.controller.hide()
    }

    @Test func dropOnASliceDeliversATypedSelection() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        let urls = [try temp.file("a.png"), try temp.file("b.png")]
        await rig.drag(urls)
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        _ = rig.controller.dragUpdated(at: rig.viewPoint(90, .pi / 2), offered: .copy)
        #expect(rig.controller.performDrop(from: rig.pasteboard))
        #expect(rig.log.selections == [WheelSelection(mode: .convert, target: .convert(.jpg), urls: urls)])
        #expect(rig.feedback.events == ["highlight", "drop"])
        rig.controller.dragEnded()
        #expect(rig.dragEnds == 1 && !rig.controller.isPointerInside)
        rig.controller.hide()
    }

    @Test func dropIsRefusedWhenTheItemsChangedOrNothingIsHighlighted() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        #expect(!rig.controller.performDrop(from: rig.pasteboard))
        _ = rig.controller.dragUpdated(at: rig.viewPoint(90, .pi / 2), offered: .copy)
        rig.pasteboard.clearContents()
        rig.pasteboard.writeObjects([try temp.file("other.png") as NSURL])
        #expect(!rig.controller.performDrop(from: rig.pasteboard))
        #expect(rig.log.selections.isEmpty)
        rig.controller.hide()
    }

    @Test func switchAndRejectChangeTheStore() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.srt")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        rig.controller.apply(.switchTo(.actions))
        #expect(rig.controller.store.model?.mode == .actions)
        rig.controller.apply(.reject(.tools, .noItemsForMode))
        #expect(rig.controller.store.pillText == "No tools for SRT files")
        #expect(rig.feedback.events == ["switch", "reject"])
        rig.controller.hide()
    }

    @Test func hideFadesOutAndResets() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        rig.controller.apply(.hide(.buttonUp))
        #expect(rig.controller.panel.ignoresMouseEvents)
        #expect(try await eventually { !rig.controller.panel.isVisible && rig.controller.store.model == nil })
    }

    @Test func aNewShowCancelsAPendingHide() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        rig.controller.hide()
        rig.controller.apply(.show(.tools, at: Point2D(x: 700, y: 400)))
        try await Task.sleep(for: .milliseconds(250))
        #expect(rig.controller.panel.isVisible && rig.controller.store.model?.mode == .tools)
        rig.controller.hide()
    }

    @Test func demoShowsAtTheScreenCentreWithAHighlight() throws {
        let rig = WheelRig()
        let demo = try #require(
            try DemoScenario.parse(arguments: ["S", "-ZivletDemoWheel", "tools", "-ZivletDemoHighlight", "1"]))
        rig.controller.showDemo(demo)
        let frame = rig.controller.panel.frame
        #expect(abs(frame.midX - 720) <= 1 && abs(frame.midY - 437.5) <= 1)
        #expect(rig.controller.store.model?.highlighted == 1)
        rig.controller.hide()
    }

    @Test func systemScreensAndAppearanceAreReadable() {
        #expect(WheelController.systemScreens().count == NSScreen.screens.count)
        let defaults = UserDefaults(suiteName: "zivlet-tests-\(UUID().uuidString)")
        defaults?.set("solid", forKey: WheelAppearance.themeKey)
        #expect(defaults.map { WheelAppearance.current(defaults: $0).theme } == .solid)
        #expect(Rect2D(CGRect(x: 1, y: 2, width: 3, height: 4)).cgRect == CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}
```

### 10.2 Run, expect failure

`swift test --filter ZivletWheelTests` → `error: cannot find type 'WheelController' in scope` (also
`WheelControllerDelegate`).

### 10.3 Implement (complete)

`wantsPeriodicDraggingUpdates()` is a method of `NSDraggingDestination`, not a property. Returning false means
updates arrive only on movement, and the highlight changes only on a slot change anyway.

`Packages/ZivletKit/Sources/ZivletWheel/WheelPanel.swift`:

```swift
import AppKit
import ZivletWheelCore

/// The pre-warmed overlay window (03a §2.1, 14 §2.1): borderless and non-activating, so Finder keeps focus and its
/// drag loop; level `.popUpMenu` (101) above shelves and the Dock; on every Space including full-screen apps
/// (collection behaviour 0x159). It ignores the mouse while hidden and never becomes key in M2.
public final class WheelPanel: NSPanel {
    public init(side: Double = WheelGeometry.standard.panelSide) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// What the drop view asks its owner. Points are in the view (y up, origin at the panel's bottom-left).
protocol WheelDropHandling: AnyObject {
    func dragEntered(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation
    func dragUpdated(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation
    func dragExited()
    func canAcceptDrop() -> Bool
    func performDrop(from pasteboard: NSPasteboard) -> Bool
    func dragEnded()
}

/// The AppKit drag destination (03a §2.5, 14 §2.2). The SwiftUI hosting view inside has no drop modifiers, so
/// AppKit walks up to this view and we keep exact control of `NSDraggingInfo`.
final class WheelDropView: NSView {
    weak var handler: (any WheelDropHandling)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        handler?.dragEntered(
            at: convert(sender.draggingLocation, from: nil), offered: sender.draggingSourceOperationMask)
            ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        handler?.dragUpdated(
            at: convert(sender.draggingLocation, from: nil), offered: sender.draggingSourceOperationMask)
            ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { handler?.dragExited() }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { handler?.canAcceptDrop() ?? false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        handler?.performDrop(from: sender.draggingPasteboard) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) { handler?.dragEnded() }
}
```

The injected `screens` and `appearance` closures are `@MainActor`: the defaults call AppKit, and a plain
`() -> [ScreenFrame]` property cannot store a main-actor function.

`Packages/ZivletKit/Sources/ZivletWheel/WheelController.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger
import ZivletWheelCore
import SwiftUI
import os

public protocol WheelControllerDelegate: AnyObject {
    func wheelController(_ controller: WheelController, didSelect selection: WheelSelection)
}

/// Owns the panel, the store and the current payload. Executes the trigger's wheel effects and answers the drop
/// view (03a §2). Nothing here converts files: a drop becomes a `WheelSelection` for the delegate.
public final class WheelController {
    public weak var delegate: (any WheelControllerDelegate)?
    /// The drag session ended on the panel (dropped or refused); the trigger host maps it to `.dropHandled`.
    public var onDragEnded: () -> Void = {}
    public private(set) var isPointerInside = false
    func isPointerInsideWheel(_ inside: Bool) { isPointerInside = inside }
    public let store: WheelStore
    let panel = WheelPanel()

    let reader: DragPayloadReader
    let builder: SliceBuilder
    let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "wheel")
    private let placer = PanelPlacer()
    private let screens: @MainActor () -> [ScreenFrame]
    private let appearance: @MainActor () -> WheelAppearance
    private(set) var payload: DragPayload?
    private var generation = 0

    public init(
        reader: DragPayloadReader, builder: SliceBuilder = SliceBuilder(),
        feedback: any WheelFeedback = SystemWheelFeedback(),
        screens: @escaping @MainActor () -> [ScreenFrame] = WheelController.systemScreens,
        appearance: @escaping @MainActor () -> WheelAppearance = { WheelAppearance.current() }
    ) {
        self.reader = reader
        self.builder = builder
        self.screens = screens
        self.appearance = appearance
        store = WheelStore(feedback: feedback)
        let side = WheelGeometry.standard.panelSide
        let dropView = WheelDropView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        let hosting = NSHostingView(rootView: WheelView(store: store))
        hosting.sizingOptions = []
        hosting.frame = dropView.bounds
        hosting.autoresizingMask = [.width, .height]
        dropView.addSubview(hosting)
        panel.contentView = dropView
        dropView.handler = self
    }

    public static func systemScreens() -> [ScreenFrame] {
        NSScreen.screens.map { ScreenFrame(frame: Rect2D($0.frame), visibleFrame: Rect2D($0.visibleFrame)) }
    }

    /// Builds the view tree and glass once at launch, off-screen at alpha 0, so the first real show only moves the
    /// panel and swaps the model (14 §2.1).
    public func prewarm() async {
        generation += 1
        let mine = generation
        let warm = WheelModel(
            mode: .actions, content: builder.content(for: .actions, items: [SelectionItem(.png)]), idleHubLabel: "")
        store.present(warm, emptyMessage: nil, appearance: appearance())
        store.expand()
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(50))
        guard mine == generation else { return }
        panel.orderOut(nil)
        store.dismiss()
    }

    public func apply(_ effect: TriggerEffect) {
        switch effect {
        case .show(let mode, let anchor):
            guard let payload = reader.latest else { return logger.error("Wheel show without a payload; ignored") }
            show(mode, at: anchor, payload: payload)
        case .switchTo(let mode): switchTo(mode)
        case .reject(let mode, _): reject(mode)
        case .hide: hide()
        default: break
        }
    }

    /// Centre on `anchor` (global, y up), clamped so the disk stays on screen; fade in over 70 ms.
    public func show(_ mode: WheelMode, at anchor: Point2D, payload: DragPayload) {
        guard let placement = placer.place(pointer: anchor, screens: screens()) else {
            return logger.error("Wheel show with no screens; ignored")
        }
        generation += 1
        self.payload = payload
        let content = builder.content(for: mode, items: payload.items)
        let model = WheelModel(
            mode: mode, content: content, idleHubLabel: HubLabel.text(for: payload.hubItems),
            hubIsCompact: HubLabel.isCompact(for: payload.hubItems))
        store.present(model, emptyMessage: emptyMessage(content), appearance: appearance())
        panel.setFrame(placement.panelFrame.cgRect, display: false)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WheelTiming.fadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        let detail = "\(mode.rawValue), \(model.slices.count) slices, \(store.theme.rawValue)"
        logger.notice("Wheel shown: \(detail, privacy: .public)")
    }

    /// DEBUG demo: the scenario's wheel at the centre of the first screen's visible frame, no drag needed.
    public func showDemo(_ scenario: DemoScenario) {
        guard let visible = screens().first?.visibleFrame else { return logger.error("Demo wheel: no screens") }
        show(scenario.mode, at: Point2D(x: visible.midX, y: visible.midY), payload: scenario.payload)
        if let slot = scenario.highlight { store.pointer(.slot(slot)) }
    }

    /// 80 ms fade, then order out and reset. A show during the fade wins.
    public func hide() {
        generation += 1
        let mine = generation
        isPointerInsideWheel(false)
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WheelTiming.hide
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishHide(mine) }
        }
    }

    private func finishHide(_ mine: Int) {
        guard mine == generation else { return }
        panel.orderOut(nil)
        store.dismiss()
        payload = nil
    }

    private func switchTo(_ mode: WheelMode) {
        guard let current = store.model, let payload else { return }
        let content = builder.content(for: mode, items: payload.items)
        store.switchTo(current.switching(to: mode, content: content), emptyMessage: emptyMessage(content))
    }

    /// The refused wheel's own reason, shown for 1.2 s while the current wheel stays (03a §1.4 T12).
    private func reject(_ mode: WheelMode) {
        let content = builder.content(for: mode, items: payload?.items ?? [])
        store.reject(message: emptyMessage(content) ?? builder.message(for: .noItems))
    }

    private func emptyMessage(_ content: WheelContent) -> String? {
        if case .empty(let reason) = content { return builder.message(for: reason) }
        return nil
    }
}

extension Rect2D {
    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
```

`Packages/ZivletKit/Sources/ZivletWheel/WheelController+Drop.swift`:

```swift
import AppKit
import ZivletCore
import ZivletWheelCore
import os

// Drop protocol (03a §2.5): hit-test on every update, negotiate a non-destructive operation, re-read the URLs at
// drop and require them to equal the probed set, then hand a typed selection to the delegate.
extension WheelController: WheelDropHandling {
    func dragEntered(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation {
        isPointerInsideWheel(true)
        return dragUpdated(at: point, offered: offered)
    }

    func dragUpdated(at point: CGPoint, offered: NSDragOperation) -> NSDragOperation {
        guard let model = store.model else { return [] }
        let centre = WheelGeometry.standard.panelSide / 2
        let hit = model.hit(Point2D(x: point.x - centre, y: point.y - centre))
        store.pointer(hit)
        let operation = DropNegotiation.operation(
            offered: DragOperations(rawValue: offered.rawValue), hit: hit, hasTarget: store.model?.dropTarget != nil)
        return NSDragOperation(rawValue: operation.rawValue)
    }

    func dragExited() {
        isPointerInsideWheel(false)
        store.pointer(.outside)
    }

    func canAcceptDrop() -> Bool { store.model?.dropTarget != nil }

    /// Returns at once; the delegate only logs and schedules UI (performDragOperation budget ≤ 1 ms).
    func performDrop(from pasteboard: NSPasteboard) -> Bool {
        let urls = DragPayloadReader.fileURLs(from: pasteboard)
        guard let payload, urls == payload.urls else {
            logger.error("Drop refused: the dragged items changed since the wheel opened")
            return false
        }
        guard let selection = store.model?.selection(urls: urls) else { return false }
        store.dropAccepted()
        delegate?.wheelController(self, didSelect: selection)
        return true
    }

    func dragEnded() {
        isPointerInsideWheel(false)
        onDragEnded()
    }
}
```

### 10.4 Verify green

`swift test --filter ZivletWheelTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 52 tests in 6 suites passed`. Run it three times. The reference run was stable 3/3 once the timing
tests used `eventually`. `make coverage` → ZivletWheel ≥ 80 % (reference 94 %).

### 10.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletWheel Packages/ZivletKit/Tests/ZivletWheelTests
git commit -s -m "feat(wheel): add pre-warmed WheelPanel, drop view and WheelController"
```

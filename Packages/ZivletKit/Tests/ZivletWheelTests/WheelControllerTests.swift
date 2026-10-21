import AppKit
import Testing
import ZivletCore
import ZivletTrigger
import ZivletWheelCore

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
        #expect(rig.controller.store.model?.hubIsCompact == false)
        rig.controller.hide()
    }

    @Test func severalItemsMakeTheHubCompact() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png"), try temp.file("b.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        #expect(rig.controller.store.model?.hubIsCompact == true)
        rig.controller.hide()
    }

    /// Collapsed on show; the on-screen view then expands it, so the intro always starts from 0.45.
    @Test func showStartsCollapsedAndTheViewExpandsIt() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        #expect(!rig.controller.store.isExpanded)
        #expect(try await eventually { rig.controller.store.isExpanded })
        rig.controller.hide()
    }

    @Test func hideInTheSameTurnAsShowNeverExpands() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        rig.controller.hide()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!rig.controller.store.isExpanded)
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

    @Test func dropCarriesTheOptionKeyStateAtRelease() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        let urls = [try temp.file("a.png")]
        await rig.drag(urls)
        rig.controller.isOptionHeld = { true }
        rig.controller.apply(.show(.actions, at: Point2D(x: 700, y: 400)))
        _ = rig.controller.dragUpdated(at: rig.viewPoint(90, .pi / 2), offered: .copy)
        #expect(rig.controller.performDrop(from: rig.pasteboard))
        let selection = try #require(rig.log.selections.first)
        #expect(selection.optionHeld && selection.mode == .actions && selection.urls == urls)
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

    @Test func unavailableTargetsAreLeftOffTheWheel() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.capabilities = CapabilitySnapshot(unavailableTargets: [.jpg, .webp])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        let targets = rig.controller.store.model?.slices.map(\.target) ?? []
        #expect(targets.first == .convert(.heic) && !targets.contains(.convert(.webp)))
        rig.controller.apply(.switchTo(.tools))
        rig.controller.apply(.switchTo(.convert))
        #expect(rig.controller.store.model?.slices.count == 5)
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

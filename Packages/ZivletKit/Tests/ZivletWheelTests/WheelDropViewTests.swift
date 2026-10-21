import AppKit
import Testing
import ZivletCore
import ZivletTrigger
import ZivletWheelCore

@testable import ZivletWheel

/// A drag session AppKit would hand the drop view: a window-space location, the source's operations and a pasteboard.
final class StubDraggingInfo: NSObject, NSDraggingInfo {
    let draggingLocation: NSPoint
    let draggingSourceOperationMask: NSDragOperation
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?

    init(location: NSPoint, operations: NSDragOperation, pasteboard: NSPasteboard, window: NSWindow?) {
        draggingLocation = location
        draggingSourceOperationMask = operations
        draggingPasteboard = pasteboard
        draggingDestinationWindow = window
    }

    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    func resetSpringLoading() {}
}

@Suite("Wheel drop view: AppKit drag callbacks → controller (03a §2.5)", .serialized)
@MainActor
struct WheelDropViewTests {
    func dropView(_ rig: WheelRig) throws -> WheelDropView {
        try #require(rig.controller.panel.contentView as? WheelDropView)
    }

    func info(_ rig: WheelRig, _ point: CGPoint, _ operations: NSDragOperation = [.copy, .move]) -> StubDraggingInfo {
        StubDraggingInfo(
            location: point, operations: operations, pasteboard: rig.pasteboard, window: rig.controller.panel)
    }

    @Test func windowPointsMapToTheWheelCentreForHitTesting() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        let view = try dropView(rig)
        // Window coordinates of the content view equal view coordinates: 90 pt above the centre is slot 0.
        #expect(view.draggingEntered(info(rig, rig.viewPoint(90, .pi / 2))) == .copy)
        #expect(rig.controller.store.model?.highlighted == 0 && rig.controller.isPointerInside)
        #expect(view.draggingUpdated(info(rig, rig.viewPoint(10, 0))) == [])
        #expect(rig.controller.store.model?.highlighted == nil)
        #expect(!view.wantsPeriodicDraggingUpdates())
        view.draggingExited(nil)
        #expect(!rig.controller.isPointerInside)
        rig.controller.hide()
    }

    @Test func dropOnASliceForwardsThePasteboardAndEndsTheSession() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        let urls = [try temp.file("a.png")]
        await rig.drag(urls)
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        let view = try dropView(rig)
        let onSlice = info(rig, rig.viewPoint(90, .pi / 2))
        _ = view.draggingUpdated(onSlice)
        #expect(view.prepareForDragOperation(onSlice))
        #expect(view.performDragOperation(onSlice))
        #expect(rig.log.selections == [WheelSelection(mode: .convert, target: .convert(.jpg), urls: urls)])
        view.draggingEnded(onSlice)
        #expect(rig.dragEnds == 1 && !rig.controller.isPointerInside)
        rig.controller.hide()
    }

    @Test func hubDropIsRefusedBeforePerform() async throws {
        let rig = WheelRig()
        let temp = try TempItems()
        await rig.drag([try temp.file("a.png")])
        rig.controller.apply(.show(.convert, at: Point2D(x: 700, y: 400)))
        let view = try dropView(rig)
        let onHub = info(rig, rig.viewPoint(5, 0))
        _ = view.draggingUpdated(onHub)
        #expect(!view.prepareForDragOperation(onHub))
        #expect(rig.log.selections.isEmpty)
        rig.controller.hide()
    }

    @Test func aViewWithoutAHandlerRefusesEverything() {
        let view = WheelDropView(frame: NSRect(x: 0, y: 0, width: 372, height: 372))
        let stub = StubDraggingInfo(
            location: .zero, operations: .copy, pasteboard: NSPasteboard.withUniqueName(), window: nil)
        #expect(view.draggingEntered(stub) == [] && view.draggingUpdated(stub) == [])
        #expect(!view.prepareForDragOperation(stub) && !view.performDragOperation(stub))
        view.draggingExited(stub)
        view.draggingEnded(stub)
    }
}

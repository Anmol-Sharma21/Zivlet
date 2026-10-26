import AppKit
import Testing
import ZivletCore
import ZivletShelfCore

@testable import ZivletBox

@Suite("Box controller (P2-55, P2-141)")
@MainActor
struct BoxControllerTests {
    @Test func startResolvesNothing() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.start()
        _ = await first.add(try rig.files(3), newBox: false)
        first.quit()
        rig.controller().start()
        #expect(rig.bookmarks.resolveCalls == 0)
    }

    @Test func showingResolvesOnceAndSavesRefreshedBookmarks() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add(files, newBox: false)
        rig.bookmarks.resolutions[files[0].standardizedFileURL.path] = .resolved(
            path: "/Users/u/Moved/f0.txt", stale: true)
        box.showPanel()
        #expect(rig.bookmarks.resolveCalls == 2)
        #expect(rig.saved()?.current?.items.first?.lastKnownPath == "/Users/u/Moved/f0.txt")
        box.press(.list)
        #expect(rig.bookmarks.resolveCalls == 2)
        box.hidePanel()
    }

    @Test func missingItemsRaiseAttention() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(3)
        _ = await box.add(files, newBox: false)
        rig.bookmarks.resolutions[files[1].standardizedFileURL.path] = .failed(
            code: 4, storedVolumePath: nil, storedVolumeName: nil)
        box.showPanel()
        #expect(box.presentation.missing == 1 && box.viewModel.missingCount == 1)
        box.hidePanel()
    }

    @Test func addingADuplicateReportsIt() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        let first = await box.add(files, newBox: false)
        let again = await box.add([files[0]], newBox: false)
        #expect(first.added == 2 && first.toast == "Added 2")
        #expect(again.added == 0 && again.duplicates == ["f0.txt"] && again.toast == nil)
    }

    @Test func optionMakesANewBox() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        _ = await box.add(try rig.files(1, prefix: "g"), newBox: true)
        #expect(box.library.boxes.count == 2 && box.library.current?.items.map(\.displayName) == ["g0.txt"])
    }

    @Test func nothingLocalIsRefusedWithZivletsWords() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let outcome = await box.add([URL(string: "https://example.com/a.png")!], newBox: false)
        #expect(outcome.added == 0 && outcome.failure == IntakeResult.nothingUsable)
    }

    @Test func aDropAddsAndOpensTheBox() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        box.showPanel()
        box.dragEntered(count: 2)
        #expect(box.presentation.overlay == .dropTarget(count: 2))
        let pasteboard = TestPasteboard(urls: try rig.files(2))
        let outcome = await box.receiveDrop(pasteboard.board)
        #expect(outcome.added == 2 && box.presentation.base == .expanded && box.presentation.overlay == nil)
        box.hidePanel()
    }

    @Test func gridAndListAreSaved() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        box.press(.list)
        #expect(rig.saved()?.current?.viewMode == .list)
        #expect(box.handleKey(BoxKeyStroke(chars: "1", command: true)))
        #expect(rig.saved()?.current?.viewMode == .grid)
    }

    @Test func escapeStepsDownAndIsSaved() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        box.showPanel()
        #expect(box.presentation.base == .expanded)
        box.panel.cancelOperation(nil)
        #expect(box.presentation.base == .docked(.right) && rig.saved()?.current?.shown == .docked(.right))
        box.press(.openPanel)
        #expect(box.presentation.base == .expanded)
        box.hidePanel()
        #expect(!box.panel.isVisible && rig.saved()?.current?.shown == .hidden)
    }

    @Test func selectionFollowsClicksAndKeys() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(4), newBox: false)
        box.showPanel()
        let ids = box.viewModel.items.map(\.id)
        box.press(.select(ids[1], extend: false, toggle: false))
        box.press(.select(ids[3], extend: true, toggle: false))
        #expect(box.viewModel.selection == Set(ids[1...3]))
        #expect(box.handleKey(BoxKeyStroke(chars: "a", command: true)) && box.viewModel.selection.count == 4)
        #expect(box.handleKey(BoxKeyStroke(special: .right)))
        box.press(.clearSelection)
        #expect(box.viewModel.selection.isEmpty)
        #expect(!box.handleKey(BoxKeyStroke(chars: "q", command: true)))
        box.hidePanel()
    }

    @Test func typeToSelectResetsAfterPoint8Seconds() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(2, prefix: "b") + rig.files(1, prefix: "c"), newBox: false)
        box.showPanel()
        _ = box.handleKey(BoxKeyStroke(chars: "c"))
        #expect(box.viewModel.selected.map(\.name) == ["c0.txt"])
        rig.clock = 0.9
        _ = box.handleKey(BoxKeyStroke(chars: "b"))
        #expect(box.viewModel.selected.map(\.name) == ["b0.txt"])
        box.hidePanel()
    }

    @Test func spaceShowsQuickLookForTheSelection() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(3)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        box.press(.select(box.viewModel.items[2].id, extend: false, toggle: false))
        #expect(box.handleKey(BoxKeyStroke(special: .space)))
        #expect(rig.quickLook.previews == [[files[2].standardizedFileURL]])
        box.press(.clearSelection)
        _ = box.handleKey(BoxKeyStroke(special: .space))
        #expect(rig.quickLook.previews.last?.count == 3)
        box.hidePanel()
    }

    @Test func aDragOutOffersEverySelectedItem() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(5)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        _ = box.handleKey(BoxKeyStroke(chars: "a", command: true))
        #expect(box.viewModel.dragURLs == files.map(\.standardizedFileURL))
        box.hidePanel()
    }

    @Test func bulkPressesGoToTheirHandlerWithTheTargets() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(3), newBox: false)
        var seen: [(BoxPress, Int)] = []
        box.onBulk = { press, items in seen.append((press, items.count)) }
        box.press(.share)
        box.press(.select(box.viewModel.items[0].id, extend: false, toggle: false))
        _ = box.handleKey(BoxKeyStroke(chars: "c", command: true))
        #expect(seen.map(\.0) == [.share, .copy] && seen.map(\.1) == [3, 1])
    }

    @Test func aPanelLetGoNearAnEdgeDocks() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        box.showPanel(.point(Point2D(x: BoxRig.display.midX, y: BoxRig.display.midY)))
        #expect(box.presentation.base == .expanded && box.presentation.dock == nil)
        let d = BoxRig.display
        box.panelMoved(to: Rect2D(x: d.minX + 10, y: d.midY, width: 384, height: 178))
        #expect(box.presentation.base == .docked(.left))
        box.hidePanel()
    }

    @Test func aNewBoxKeyMakesAnEmptyCurrentBox() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        #expect(box.handleKey(BoxKeyStroke(chars: "n", command: true)))
        #expect(box.library.boxes.count == 2 && box.library.current?.items.isEmpty == true)
    }
}

@Suite("Marquee in the grid (17e §2.3)")
@MainActor
struct BoxMarqueeTests {
    @Test func aMarqueeSelectsTheCellsItCrosses() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        _ = await box.add(try rig.files(7), newBox: false)
        box.showPanel()
        let ids = box.viewModel.items.map(\.id)
        box.press(.marquee(Rect2D(x: 60, y: 60, width: 20, height: 20)))
        #expect(box.viewModel.selection == [ids[0], ids[1], ids[5], ids[6]])
        box.press(.marquee(Rect2D(x: 900, y: 900, width: 1, height: 1)))
        #expect(box.viewModel.selection.isEmpty)
        box.hidePanel()
    }

    @Test func theGridsCellsFollowTheTokens() {
        let cells = BoxGrid.cells(count: 6)
        #expect(cells[5].minY == Double(BoxLook.Grid.rowHeight + BoxLook.Grid.gap) && cells[1].minX == 72)
    }
}

@Suite("Marquee rectangle from a drag")
struct BoxMarqueeRectTests {
    @Test func aDragUpAndLeftStillMakesAPositiveRectangle() {
        #expect(
            BoxGrid.rect(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 0))
                == Rect2D(x: 10, y: 0, width: 40, height: 40))
    }
}

@Suite("What the controller reports for the logs and the demo scripts")
@MainActor
struct BoxControllerReportTests {
    @Test func eachNewStateAndFrameIsReportedOnce() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        var reports: [String] = []
        box.onPresented = { base, frame in reports.append("\(base.stored) \(frame == nil ? "none" : "frame")") }
        box.start()
        _ = await box.add(try rig.files(1), newBox: false)
        box.showPanel()
        box.press(.select(box.viewModel.items[0].id, extend: false, toggle: false))
        box.hidePanel()
        #expect(reports == ["hidden none", "expanded frame", "hidden none"])
    }
}

import AppKit
import Testing
import ZivletCore
import ZivletShelfCore

@testable import ZivletBox

@Suite("Restore after relaunch (P2-55 §9.5)")
@MainActor
struct BoxRestoreTests {
    @Test func theBoxComesBackWhereItWas() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.start()
        _ = await first.add(try rig.files(3), newBox: false)
        first.showPanel()
        first.dock(.right)
        first.quit()
        let resolvedBefore = rig.bookmarks.resolveCalls
        let second = rig.controller()
        second.start()
        #expect(second.presentation.base == .docked(.right) && second.library.current?.items.count == 3)
        #expect(rig.bookmarks.resolveCalls == resolvedBefore)  // lazy: nothing resolved until shown
        #expect(second.panel.isVisible)
        second.hidePanel()
    }

    @Test func aMovedPanelComesBackAtItsFrame() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.start()
        _ = await first.add(try rig.files(2), newBox: false)
        first.showPanel()
        let moved = Rect2D(x: BoxRig.display.minX + 400, y: BoxRig.display.minY + 300, width: 384, height: 178)
        first.panelMoved(to: moved)
        first.quit()
        let second = rig.controller()
        second.start()
        #expect(second.presentation.base == .expanded && second.presentation.dock == nil)
        #expect(second.library.current?.frame == moved)
        #expect(Rect2D(second.panel.frame).maxY == moved.maxY)
        second.hidePanel()
    }

    @Test func aHiddenBoxStaysHidden() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.start()
        _ = await first.add(try rig.files(1), newBox: false)
        first.quit()
        let second = rig.controller()
        second.start()
        #expect(second.presentation.base == .hidden && !second.panel.isVisible)
    }

    @Test func aFrameOnADisplayThatIsGoneMovesToTheFirstOne() async throws {
        let rig = try BoxRig()
        let first = rig.controller()
        first.start()
        _ = await first.add(try rig.files(1), newBox: false)
        first.showPanel()
        first.panelMoved(
            to: Rect2D(x: BoxRig.display.maxX + 2000, y: BoxRig.display.minY + 100, width: 384, height: 178))
        first.quit()
        let second = rig.controller()
        second.start()
        let frame = Rect2D(second.panel.frame)
        #expect(frame.maxX <= BoxRig.display.maxX && frame.minX >= BoxRig.display.minX)
        second.hidePanel()
    }
}

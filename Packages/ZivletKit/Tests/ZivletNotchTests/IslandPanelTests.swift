import AppKit
import Testing

@testable import ZivletNotch

@Suite("Island panel (D-N2)")
@MainActor
struct IslandPanelTests {
    @Test func nonActivatingAboveTheMenuBarOnEverySpace() {
        let panel = IslandPanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
        #expect(panel.level == .statusBar)
        #expect(
            panel.collectionBehavior.isSuperset(of: [
                .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
            ]))
        #expect(!panel.hidesOnDeactivate && !panel.isMovable && !panel.hasShadow && !panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
    }

    @Test func keyOnlyAfterAClickNeverMain() {
        let panel = IslandPanel()
        #expect(panel.canBecomeKey && panel.becomesKeyOnlyIfNeeded && !panel.canBecomeMain)
    }

    @Test func belowTheWheelAndOpenMenus() { #expect(IslandPanel().level.rawValue < NSWindow.Level.popUpMenu.rawValue) }

    @Test func escapeIsReportedInsteadOfClosingThePanel() {
        let panel = IslandPanel()
        var escapes = 0
        panel.onEscape = { escapes += 1 }
        panel.cancelOperation(nil)
        #expect(escapes == 1)
    }
}

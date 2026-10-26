import AppKit
import SwiftUI
import Testing

@testable import ZivletBox

@Suite("Drop Box panel (P2-55: non-activating, every Space)")
@MainActor
struct BoxPanelTests {
    @Test func itFloatsOnEverySpaceWithoutActivating() {
        let panel = BoxPanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
        #expect(panel.canBecomeKey && !panel.canBecomeMain && !panel.becomesKeyOnlyIfNeeded)
        #expect(panel.appearance?.name == .darkAqua)
        #expect(!panel.hidesOnDeactivate && !panel.isOpaque && panel.hasShadow && panel.backgroundColor == .clear)
        #expect(panel.isMovableByWindowBackground)
    }

    @Test func showingDoesNotTakeTheKeyboard() {
        let panel = BoxPanel()
        panel.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        panel.show()
        #expect(panel.isVisible && !panel.isKeyWindow)
        panel.orderOut(nil)
    }

    @Test func aRealClickOnItsContentMakesItKey() throws {
        let panel = BoxPanel()
        panel.contentView = NSHostingView(rootView: Color.black.frame(width: 200, height: 120))
        panel.setFrame(NSRect(x: -5000, y: -5000, width: 200, height: 120), display: false)
        panel.show()
        defer { panel.orderOut(nil) }
        let point = NSPoint(x: 100, y: 60)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            panel.sendEvent(event)
        }
        #expect(panel.isKeyWindow)
    }

    @Test func aClickMakesItKeyAndEscapeReachesTheClosure() {
        let panel = BoxPanel()
        var escapes = 0
        var keyChanges: [Bool] = []
        panel.onEscape = { escapes += 1 }
        panel.onKeyChange = { keyChanges.append($0) }
        panel.becomeKey()
        panel.cancelOperation(nil)
        panel.resignKey()
        #expect(escapes == 1 && keyChanges == [true, false])
    }

    @Test func keysGoToTheControllerFirst() throws {
        let panel = BoxPanel()
        var seen: [String] = []
        panel.onKey = { event in
            seen.append(event.charactersIgnoringModifiers ?? "")
            return true
        }
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        panel.keyDown(with: event)
        #expect(seen == ["a"])
    }

    @Test func aMoveIsReportedWhenTheButtonComesUp() {
        let panel = BoxPanel()
        var moves: [NSRect] = []
        panel.onMoveEnded = { moves.append($0) }
        panel.setFrame(NSRect(x: -5000, y: -5000, width: 100, height: 100), display: false)
        panel.pressBegan()
        panel.setFrameOrigin(NSPoint(x: -4990, y: -5000))
        panel.pressEnded()
        panel.pressBegan()
        panel.pressEnded()
        #expect(moves == [NSRect(x: -4990, y: -5000, width: 100, height: 100)])
    }
}

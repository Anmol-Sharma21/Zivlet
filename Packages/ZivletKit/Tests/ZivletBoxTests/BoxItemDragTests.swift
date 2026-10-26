import AppKit
import Testing
import ZivletActions

@Suite("Shared drag source in the box: clicks select, drags carry files")
@MainActor
struct BoxItemDragTests {
    private func mouse(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func aPressWithoutADragIsAClickWithItsKeys() throws {
        let view = DragSourceView(urls: [], image: NSImage())
        var clicks: [NSEvent.ModifierFlags] = []
        view.onClick = { clicks.append($0) }
        view.mouseDown(with: try mouse(.leftMouseDown))
        view.mouseUp(with: try mouse(.leftMouseUp, flags: .shift))
        #expect(clicks == [.shift])
    }

    @Test func aPressThatDragsIsNotAClick() throws {
        let view = DragSourceView(urls: [], image: NSImage())
        var clicks = 0
        view.onClick = { _ in clicks += 1 }
        view.mouseDown(with: try mouse(.leftMouseDown))
        view.mouseDragged(with: try mouse(.leftMouseDragged))
        view.mouseUp(with: try mouse(.leftMouseUp))
        #expect(clicks == 0)
    }

    @Test func aDragNeverMovesTheWindow() {
        let view = DragSourceView(urls: [], image: NSImage())
        #expect(!view.mouseDownCanMoveWindow)
        view.drawsImage = false
        view.draw(view.bounds)
    }
}

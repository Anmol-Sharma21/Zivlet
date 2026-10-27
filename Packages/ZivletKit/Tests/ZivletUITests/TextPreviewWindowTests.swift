import AppKit
import Testing
import ZivletActions

@testable import ZivletUI

@Suite("Show All (P2-104, plan 18d D11): a read-only, selectable text window")
@MainActor
struct TextPreviewWindowTests {
    @Test func theTitleNamesTheFileOrTheCount() {
        #expect(TextPreviewModel.title(names: ["photo.png"]) == "Text from photo.png")
        #expect(TextPreviewModel.title(names: ["a.png", "b.pdf", "c.jpg"]) == "Text from 3 files")
    }

    @Test func theWindowHoldsTheWholeTextReadOnlyAndSelectable() {
        let window = TextPreviewWindow()
        defer { window.close() }
        window.load(TextPreviewModel(title: "Text from photo.png", text: "पहली पंक्ति\nSecond line\n"))
        #expect(window.title == "Text from photo.png")
        #expect(window.textView.string == "पहली पंक्ति\nSecond line\n")
        #expect(!window.textView.isEditable && window.textView.isSelectable)
        #expect(!window.isVisible)
    }

    @Test func escapeAndCommandWClose() throws {
        let window = TextPreviewWindow()
        window.load(TextPreviewModel(title: "t", text: "x"))
        window.setFrameOrigin(CGPoint(x: -5_000, y: -5_000))
        window.orderFrontRegardless()
        window.cancelOperation(nil)
        #expect(!window.isVisible)
        window.orderFrontRegardless()
        let commandW = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        #expect(window.performKeyEquivalent(with: commandW))
        #expect(!window.isVisible)
    }

    @Test func reduceTransparencyGetsTheSolidBackground() {
        #expect(TextPreviewWindow.usesGlass(reduceTransparency: false))
        #expect(!TextPreviewWindow.usesGlass(reduceTransparency: true))
    }

    @Test func theWindowNeverActivatesTheApp() {
        let window = TextPreviewWindow()
        defer { window.close() }
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.canBecomeKey)
    }
}

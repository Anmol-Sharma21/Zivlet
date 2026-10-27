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

    static func command(_ key: String, code: UInt16) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
    }

    /// Zivlet has no main menu (it lives in the menu bar), so the window answers ⌘A and ⌘C itself.
    @Test func commandASelectsAllAndCommandCCopies() throws {
        let window = TextPreviewWindow()
        defer { window.close() }
        window.load(TextPreviewModel(title: "t", text: "पहली पंक्ति\nSecond line\n"))
        #expect(window.performKeyEquivalent(with: try Self.command("a", code: 0)))
        let all = NSRange(location: 0, length: (window.textView.string as NSString).length)
        #expect(window.textView.selectedRange() == all)
        #expect(window.performKeyEquivalent(with: try Self.command("c", code: 8)))
    }

    @Test func commandCWritesTheSelectionForThisMacOnly() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("zivlet-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let window = TextPreviewWindow(clipboard: ClipboardAction(pasteboard: board))
        defer { window.close() }
        window.load(TextPreviewModel(title: "t", text: "पहली पंक्ति\nSecond line\n"))
        window.textView.setSelectedRange(NSRange(location: 0, length: 11))
        #expect(window.performKeyEquivalent(with: try Self.command("c", code: 8)))
        #expect(board.string(forType: .string) == "पहली पंक्ति")
    }

    @Test func aChangeOfDisplayOptionsRedrawsTheSurfaceAtOnce() {
        let window = TextPreviewWindow()
        defer { window.close() }
        window.applyBackground(reduceTransparency: false, increaseContrast: false)
        #expect(window.contentView is NSGlassEffectView && !window.hasOutline)
        window.applyBackground(reduceTransparency: true, increaseContrast: false)
        #expect(!(window.contentView is NSGlassEffectView) && !window.hasOutline)
        window.applyBackground(reduceTransparency: false, increaseContrast: true)
        #expect(!(window.contentView is NSGlassEffectView) && window.hasOutline)
        #expect(window.textView.enclosingScrollView?.superview === window.contentView)
    }

    @Test func reduceTransparencyGetsTheSolidBackground() {
        #expect(TextPreviewWindow.usesGlass(reduceTransparency: false))
        #expect(!TextPreviewWindow.usesGlass(reduceTransparency: true))
        #expect(!TextPreviewWindow.usesGlass(reduceTransparency: false, increaseContrast: true))
    }

    @Test func theWindowNeverActivatesTheApp() {
        let window = TextPreviewWindow()
        defer { window.close() }
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.canBecomeKey)
    }
}

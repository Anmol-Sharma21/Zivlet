import AppKit
import SwiftUI
import Testing
import ZivletNotch
import ZivletNotchCore

@testable import ZivletUI

@Suite("The tool window (P2-30, plan 20b A2, D-M7-10): key without activating, Esc and Return, glass and fallbacks")
@MainActor
struct ToolWindowTests {
    static let reason = DisabledReason("Passwords don't match")
    static let lock = ToolWindowModel(
        symbol: "lock.doc", title: "Lock", fileLine: "Report.pdf", apply: .enabled(label: "Lock"))

    /// A window loaded with `model`, on screen far outside every display, with counters for its two actions.
    final class Harness {
        let window = ToolWindow()
        var applied = 0
        var cancelled = 0

        init(_ model: ToolWindowModel) {
            window.onApply = { [unowned self] in applied += 1 }
            window.onCancel = { [unowned self] in cancelled += 1 }
            window.load(model, content: AnyView(Text("content")))
            window.setFrameOrigin(CGPoint(x: -5_000, y: -5_000))
            window.orderFrontRegardless()
        }
    }

    static func key(_ characters: String, code: UInt16) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    static func command(_ key: String, code: UInt16, shift: Bool = false) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false,
                keyCode: code))
    }

    /// A field stand-in that records the editing commands it is sent.
    final class EditingProbe: NSView {
        var received: [String] = []
        override var acceptsFirstResponder: Bool { true }
        @objc func paste(_ sender: Any?) { received.append("paste") }
        @objc func copy(_ sender: Any?) { received.append("copy") }
        @objc func cut(_ sender: Any?) { received.append("cut") }
        override func selectAll(_ sender: Any?) { received.append("selectAll") }
        @objc func undo(_ sender: Any?) { received.append("undo") }
        @objc func redo(_ sender: Any?) { received.append("redo") }
    }

    /// Zivlet has no main menu, so no Edit menu turns ⌘V into paste: the window does it for the field with the keyboard
    /// (a pasted password is Unlock's main path).
    @Test func theEditingKeysReachTheFieldThatHasTheKeyboard() throws {
        let harness = Harness(Self.lock)
        defer { harness.window.close() }
        let probe = EditingProbe(frame: .zero)
        harness.window.contentView?.addSubview(probe)
        #expect(harness.window.makeFirstResponder(probe))
        let keys: [NSEvent] = [
            try Self.command("v", code: 9), try Self.command("c", code: 8), try Self.command("x", code: 7),
            try Self.command("a", code: 0), try Self.command("z", code: 6), try Self.command("z", code: 6, shift: true),
        ]
        for key in keys { #expect(harness.window.performKeyEquivalent(with: key)) }
        #expect(probe.received == ["paste", "copy", "cut", "selectAll", "undo", "redo"])
        #expect(!harness.window.performKeyEquivalent(with: try Self.command("q", code: 12)))
    }

    @Test func itIsABorderlessNonActivatingPanelThatCanBecomeKey() {
        let window = ToolWindow()
        defer { window.close() }
        #expect(window.canBecomeKey && !window.canBecomeMain)
        #expect(window.styleMask.contains(.nonactivatingPanel) && window.styleMask.contains(.borderless))
        #expect(!window.hidesOnDeactivate && window.level == .floating)
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
    }

    @Test func escapeRunsCancelAndCloses() {
        let harness = Harness(Self.lock)
        harness.window.cancelOperation(nil)
        #expect(harness.cancelled == 1 && harness.applied == 0)
        #expect(!harness.window.isVisible)
    }

    @Test func returnRunsApplyWhenItIsOn() throws {
        let harness = Harness(Self.lock)
        defer { harness.window.close() }
        harness.window.keyDown(with: try Self.key("\r", code: 36))
        harness.window.keyDown(with: try Self.key("\u{3}", code: 76))
        #expect(harness.applied == 2 && harness.cancelled == 0)
    }

    @Test func returnDoesNothingWhenApplyIsOffOrTheToolIsWorking() throws {
        let reason = try #require(Self.reason)
        let harness = Harness(Self.lock.with(apply: .disabled(label: "Lock", reason: reason)))
        defer { harness.window.close() }
        harness.window.keyDown(with: try Self.key("\r", code: 36))
        harness.window.update(Self.lock.busy())
        harness.window.keyDown(with: try Self.key("\r", code: 36))
        #expect(harness.applied == 0)
        #expect(harness.window.isVisible)
    }

    @Test func closingDropsTheContentAndTheModel() {
        let harness = Harness(Self.lock)
        harness.window.close()
        #expect(harness.window.state.model == nil && harness.window.state.content == nil)
    }

    @Test func glassUnlessReduceTransparencyOrIncreaseContrast() {
        #expect(ToolWindow.usesGlass(reduceTransparency: false, increaseContrast: false))
        #expect(!ToolWindow.usesGlass(reduceTransparency: true, increaseContrast: false))
        #expect(!ToolWindow.usesGlass(reduceTransparency: false, increaseContrast: true))
        let window = ToolWindow()
        defer { window.close() }
        window.applyDisplayOptions(reduceTransparency: false, increaseContrast: true)
        #expect(window.state.finish == .solid(band: 0, outline: true))
        window.applyDisplayOptions(reduceTransparency: true, increaseContrast: false)
        #expect(window.state.finish == .solid(band: 0, outline: false))
        window.applyDisplayOptions(reduceTransparency: false, increaseContrast: false)
        #expect(window.state.finish == .glass(band: 0))
    }

    @Test func aForcedFinishWinsOverTheSystemsUntilItIsCleared() {
        let window = ToolWindow()
        defer { window.close() }
        window.finishOverride = IslandFinish.Settings(reduceTransparency: false, increaseContrast: true)
        #expect(window.state.finish == .solid(band: 0, outline: true))
        window.finishOverride = IslandFinish.Settings(reduceTransparency: true, increaseContrast: false)
        #expect(window.state.finish == .solid(band: 0, outline: false))
        window.finishOverride = nil
        let workspace = NSWorkspace.shared
        let system = IslandFinish.floating(
            settings: IslandFinish.Settings(
                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast))
        #expect(window.state.finish == system)
    }

    @Test func voiceOverHearsTheToolsNameAndWhyApplyIsOff() throws {
        let harness = Harness(Self.lock)
        defer { harness.window.close() }
        #expect(harness.window.accessibilityLabel() == "Lock")
        let reason = try #require(Self.reason)
        #expect(
            ToolWindowView.applyLabel(.disabled(label: "Lock", reason: reason)) == "Lock, unavailable: \(reason.text)")
        #expect(ToolWindowView.applyLabel(.enabled(label: "Lock")) == "Lock")
    }

    @Test func theSecondaryInkHoldsItsContrastOnEveryFinish() {
        #expect(
            IslandInk.contrast(textOpacity: IslandInk.secondaryOpacity, over: IslandLook.worstGlassLuminance) >= 4.5)
        let solid = IslandInk.luminance(IslandLook.solidGrey)
        #expect(IslandInk.contrast(textOpacity: IslandInk.secondaryOpacity, over: solid) >= 4.5)
    }

    /// Content that grows after the window opened near the bottom of the screen (a restriction picked, Unlock turned
    /// into Change) moves the window up rather than below the screen's edge.
    @Test func contentGrowingAtTheBottomEdgeKeepsTheWindowOnScreen() {
        let window = ToolWindow()
        defer { window.close() }
        // A visible frame far outside every display: the window is shown, as a real one is, but never seen.
        let screen = CGRect(x: -6_000, y: -6_000, width: 1440, height: 800)
        window.load(Self.lock, content: AnyView(Color.clear.frame(height: 100)))
        window.place(at: CGPoint(x: -5_300, y: -6_000), visibleFrame: screen)
        window.orderFrontRegardless()
        let placed = window.frame
        window.load(Self.lock, content: AnyView(Color.clear.frame(height: 300)))
        #expect(window.frame.height > placed.height)
        #expect(window.frame.minY >= screen.minY + ToolWindowPlacement.margin)
    }

    @Test func voiceOverHearsTheNewTitleAfterAnUpdate() {
        let harness = Harness(Self.lock)
        defer { harness.window.close() }
        harness.window.update(
            ToolWindowModel(
                symbol: "lock.rotation", title: "Change password", fileLine: "Report.pdf",
                apply: .enabled(label: "Change")))
        #expect(harness.window.accessibilityLabel() == "Change password")
    }

    @Test func showingPlacesItAtTheWheelAndSizesItToItsContent() {
        let window = ToolWindow()
        defer { window.close() }
        window.load(Self.lock, content: AnyView(Text("content")))
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        window.place(at: CGPoint(x: 700, y: 400), visibleFrame: screen)
        #expect(window.frame.width == ToolWindowView.width)
        #expect(window.frame.height > 0)
        #expect(abs(window.frame.midX - 700) < 1 && abs(window.frame.midY - 400) < 1)
    }
}

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

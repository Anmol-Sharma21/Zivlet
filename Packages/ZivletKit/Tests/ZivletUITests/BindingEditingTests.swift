import Testing
import ZivletActions
import ZivletCore
import ZivletSettings
import ZivletTrigger

@testable import ZivletUI

@Suite("Binding editing keeps three distinct modifiers (D3)")
struct BindingEditingTests {
    @Test func choosingAUsedModifierSwapsTheTwo() {
        let edited = BindingEditing.set(.command, for: .convert, in: .standard)  // ⇧/⌘/⌃ → ⌘/⇧/⌃
        #expect(edited.modifier(for: .convert) == .command && edited.modifier(for: .tools) == .shift)
        #expect(Set(WheelMode.allCases.map(edited.modifier(for:))).count == 3)
    }

    @Test func choosingAFreeModifierJustReplaces() {
        let edited = BindingEditing.set(.option, for: .actions, in: .standard)
        #expect(edited.modifier(for: .actions) == .option && edited.modifier(for: .tools) == .command)
    }

    @Test func choosingTheSameModifierChangesNothing() {
        #expect(BindingEditing.set(.shift, for: .convert, in: .standard) == .standard)
    }

    @Test func theFourChoicesAreTheSingleModifiers() {
        #expect(BindingEditing.choices.map(\.mask) == [.shift, .command, .control, .option])
        #expect(BindingEditing.choices.map(\.title) == ["⇧ Shift", "⌘ Command", "⌃ Control", "⌥ Option"])
    }
}

@Suite("Settings model writes through the store's transform (D3)")
@MainActor
struct SettingsModelTests {
    @Test func setWritesACopyAndKeepsTheResult() {
        let model = SettingsModel.preview
        model.set(\.feedback.sound, false)
        #expect(!model.settings.feedback.sound)
        model.setModifier(.control, for: .convert)
        #expect(model.settings.trigger.bindings.modifier(for: .actions) == .shift)
    }

    @Test func aRefusedWriteShowsTheStoredValue() {
        let model = SettingsModel(
            settings: .defaults, installedTerminals: [], commands: SettingsCommands(write: { _ in .defaults }))
        model.set(\.actions.terminal, "bad id")
        #expect(model.settings.actions.terminal == "com.apple.Terminal")
    }

    @Test func refreshShowsChangesMadeElsewhere() {
        let model = SettingsModel.preview
        model.refresh(Settings.defaults.with(\.trigger.paused, true))
        #expect(model.settings.trigger.paused)
    }

    @Test func aStoredTerminalThatIsNotInstalledStaysChoosable() {
        let model = SettingsModel(
            settings: Settings.defaults.with(\.actions.terminal, TerminalApp.warp.id),
            installedTerminals: [.terminal], commands: .preview)
        #expect(model.terminalChoices.map(\.name) == ["Terminal", "Warp"])
    }
}

import Foundation
import Testing
import ZivletCore

@testable import ZivletUI

/// Suggest (P2-101, plan 20c B5, D-M7-27): a strong password fills both fields, revealed. Automation only ever uses the
/// fake; the system's generator is tried by the owner (OS-M7-4).
@Suite("Suggest a strong password")
@MainActor
struct PasswordSuggesterTests {
    /// The system's shape (four groups of three), made up here per run.
    private static func made() -> String {
        let letters = Array("abcdefghjkmnpqrstuvwxyz")
        let group = { String((0..<3).map { _ in letters.randomElement()! }) }
        return "\(group())-\(group().uppercased())-\(Int.random(in: 100...999))-\(group())"
    }

    private func sheet(_ mode: PasswordMode, suggester: (any PasswordSuggesting)?) -> PasswordSheetState {
        PasswordSheetState(
            model: PasswordSheetModel(mode: mode, files: ["Report.pdf"]), suggester: suggester, announce: { _ in })
    }

    @Test func suggestFillsBothFieldsAlikeAndRevealsThem() {
        let text = Self.made()
        let state = sheet(.lock, suggester: FakeSuggester(text))
        #expect(state.canSuggest)
        state.suggest()
        #expect(state.password == text && state.confirm == text)
        #expect(state.model.revealed == [.password, .confirm])
        #expect(state.model.strength == .strong)
        #expect(state.model.apply == .enabled(label: "Lock"))
    }

    /// Change's Suggest shows the new password, never the file's current one (screen sharing, a look over a shoulder).
    @Test func suggestInChangeLeavesTheCurrentPasswordHidden() {
        let state = sheet(.change, suggester: FakeSuggester(Self.made()))
        state.current = "the file's own password"
        state.suggest()
        let labels = PasswordSheetView.controlLabels(state.model, canSuggest: true)
        #expect(
            Array(labels.prefix(6)) == [
                "Current password", "Show password", "New password", "Hide password", "Confirm", "Hide password",
            ])
    }

    @Test func aSuggesterWithNothingHidesTheButton() {
        let state = sheet(.lock, suggester: FakeSuggester(nil))
        state.password = "typed"
        state.suggest()
        #expect(!state.canSuggest)
        #expect(state.password == "typed" && state.confirm.isEmpty)
    }

    @Test func thereIsNoSuggestWithoutASuggesterOrWhereNoPasswordIsSet() {
        #expect(!sheet(.lock, suggester: nil).canSuggest)
        #expect(!sheet(.unlock, suggester: FakeSuggester(Self.made())).canSuggest)
        #expect(sheet(.change, suggester: FakeSuggester(Self.made())).canSuggest)
    }

    @Test func theFakeCountsItsCalls() {
        let fake = FakeSuggester(Self.made())
        let state = sheet(.lock, suggester: fake)
        state.suggest()
        state.suggest()
        #expect(fake.calls == 2)
    }

    @Test func theSuggestButtonIsListedOnlyWhenItCanSuggest() {
        let state = sheet(.lock, suggester: FakeSuggester(Self.made()))
        #expect(PasswordSheetView.controlLabels(state.model, canSuggest: state.canSuggest).contains("Suggest"))
        let none = sheet(.lock, suggester: nil)
        #expect(!PasswordSheetView.controlLabels(none.model, canSuggest: none.canSuggest).contains("Suggest"))
    }
}

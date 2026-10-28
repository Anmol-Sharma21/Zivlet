import Testing
import ZivletCore

@testable import ZivletUI

/// The password sheet's states (P2-101, plan 20c B3): what Apply says, which fields and notes show, wrong attempts,
/// the batch switch and the second sheet. The model holds facts about the typed text, never the text.
@Suite("The password sheet's states")
struct PasswordSheetModelTests {
    static let lock = PasswordSheetModel(mode: .lock, files: ["Report.pdf"])
    static let unlock = PasswordSheetModel(mode: .unlock, files: ["Report.pdf"])

    private func typed(
        _ model: PasswordSheetModel, password: String, confirm: String = "", current: String = ""
    ) -> PasswordSheetModel {
        model.entered(PasswordEntry(password: password, confirm: confirm, current: current))
    }

    @Test func lockWithNothingTypedAsksForAPassword() {
        #expect(Self.lock.apply == .disabled(label: "Lock", reason: DisabledReason("Type a password")!))
    }

    @Test func lockWithAMismatchSaysSo() {
        let model = typed(Self.lock, password: "open sesame", confirm: "open sesam")
        #expect(model.apply.reason == "Passwords don't match")
        #expect(!model.apply.isEnabled)
    }

    @Test func lockWithAMatchIsOn() {
        let model = typed(Self.lock, password: "open sesame", confirm: "open sesame")
        #expect(model.apply == .enabled(label: "Lock"))
    }

    @Test func aPDFPasswordOver127BytesIsRefusedBeforeTheMismatch() {
        let long = String(repeating: "प", count: 43)
        let model = typed(Self.lock, password: long, confirm: "x")
        #expect(model.apply.reason == "Use 127 bytes or fewer")
    }

    @Test func aNonASCIIPasswordShowsTheNoteAndLockStaysOn() {
        let model = typed(Self.lock, password: "पासवर्ड-2026", confirm: "पासवर्ड-2026")
        #expect(model.notes == [.nonASCIIPDF])
        #expect(model.apply.isEnabled)
        #expect(typed(Self.lock, password: "open sesame", confirm: "open sesame").notes.isEmpty)
    }

    @Test func theStrengthFollowsThePasswordInLockAndChangeOnly() {
        #expect(typed(Self.lock, password: "Gx7!pLq2#vR9").strength == .strong)
        #expect(Self.lock.strength == nil)
        #expect(typed(Self.unlock, password: "Gx7!pLq2#vR9").strength == nil)
    }

    @Test func unlockIsOnWhenItsFieldHasText() {
        #expect(Self.unlock.apply.reason == "Type a password")
        #expect(typed(Self.unlock, password: "x").apply == .enabled(label: "Unlock"))
    }

    @Test func eachWrongAttemptCountsUpWithNoLimit() {
        let twice = Self.unlock.wrongAttempt().wrongAttempt()
        #expect(twice.failure == .wrong(attempt: 2))
        let many = (0..<20).reduce(Self.unlock) { model, _ in model.wrongAttempt() }
        #expect(many.failure == .wrong(attempt: 20))
        #expect(typed(many, password: "again").apply.isEnabled)
    }

    @Test func aWrongAttemptIsAnnouncedAndExplained() {
        let model = Self.unlock.wrongAttempt()
        #expect(model.announcement == "Wrong password")
        #expect(model.errorLine == "That password didn't work.")
        #expect(Self.unlock.announcement == nil)
        #expect(Self.unlock.errorLine == nil)
    }

    @Test func sameForAllIsOnByDefaultOnlyForSeveralFiles() {
        let three = PasswordSheetModel(mode: .unlock, files: ["a.pdf", "b.pdf", "c.pdf"])
        #expect(three.sameForAll)
        #expect(three.sameForAllLabel == "Use the same password for all 3 files")
        #expect(!Self.unlock.sameForAll)
        #expect(Self.unlock.sameForAllLabel == nil)
        #expect(!three.with(sameForAll: false).sameForAll)
    }

    @Test func theSecondSheetListsExactlyTheFilesThatFailed() {
        let three = PasswordSheetModel(mode: .unlock, files: ["a.pdf", "b.pdf", "c.pdf"]).wrongAttempt()
        let retry = three.retry(names: ["b.pdf", "c.pdf"])
        #expect(retry.retryList == ["b.pdf", "c.pdf"])
        #expect(retry.retryTitle == "These didn't open:")
        #expect(retry.failure == nil)
        #expect(retry.mode == .unlock)
        #expect(retry.fileLine == "2 files")
        #expect(Self.unlock.retryTitle == nil)
        #expect(retry.changeSwitchLabel == nil)
    }

    @Test func unlockCanTurnIntoChangeWithThreeFields() {
        #expect(Self.unlock.changeSwitchLabel == "Change password…")
        let change = Self.unlock.switchedToChange()
        #expect(change.mode == .change)
        #expect(change.fields == [.current, .newPassword, .confirm])
        #expect(change.changeSwitchLabel == nil)
        #expect(change.apply.label == "Change")
        #expect(change.labelsFields)
        #expect(!Self.lock.labelsFields && !Self.unlock.labelsFields)
    }

    @Test func eachModeShowsItsFields() {
        #expect(Self.lock.fields == [.password, .confirm])
        #expect(Self.unlock.fields == [.password])
        #expect(PasswordSheetModel(mode: .ownerNeeded, files: ["a.pdf"]).fields == [.password])
        #expect(PasswordField.current.label == "Current password")
        #expect(PasswordField.newPassword.label == "New password")
        #expect(PasswordField.password.label == "Password")
        #expect(PasswordField.confirm.label == "Confirm")
    }

    @Test func changeNeedsTheCurrentPasswordAndAMatch() {
        let change = Self.unlock.switchedToChange()
        #expect(typed(change, password: "new one", confirm: "new one").apply.reason == "Type the current password")
        let mismatch = typed(change, password: "new one", confirm: "new", current: "old")
        #expect(mismatch.apply.reason == "Passwords don't match")
        #expect(typed(change, password: "new one", confirm: "new one", current: "old").apply.isEnabled)
    }

    @Test func theFooterShowsWhereAPasswordIsAskedFor() {
        let footer =
            "Zivlet can't recover forgotten passwords. Try the password again, or ask the person who sent the file."
        #expect(Self.unlock.footer == footer)
        #expect(PasswordSheetModel(mode: .ownerNeeded, files: ["a.pdf"]).footer == footer)
        #expect(Self.lock.footer == nil)
    }

    @Test func ownerNeededExplainsWhy() {
        let model = PasswordSheetModel(mode: .ownerNeeded, files: ["a.pdf"])
        #expect(model.notes == [.restrictionsNeedOwner])
        #expect(model.apply.label == "Unlock")
    }

    @Test func revealingIsAValueChange() {
        let shown = Self.lock.with(revealed: true)
        #expect(shown.revealed)
        #expect(!Self.lock.revealed)
    }

    @Test func theShellGetsTheToolsHeaderAndApply() {
        let shell = typed(Self.lock, password: "a", confirm: "a").window
        #expect(shell.title == "Lock")
        #expect(shell.symbol == "lock")
        #expect(shell.fileLine == "Report.pdf")
        #expect(shell.apply.isEnabled)
        #expect(Self.unlock.window.symbol == "lock.open")
        #expect(Self.unlock.switchedToChange().window.title == "Change password")
    }

    @Test func notesHaveTheirWordsAndSymbol() {
        let warning = "Preview on Mac can't open PDFs whose password uses non-English letters."
        #expect(PasswordNote.nonASCIIPDF.text == warning)
        #expect(PasswordNote.nonASCIIPDF.symbol == "exclamationmark.triangle")
        #expect(!PasswordNote.restrictionsNeedOwner.text.isEmpty)
    }
}

import Foundation
import Testing
import ZivletCore

@testable import ZivletUI

/// A locked PDF in Copy Text or Read QR (P2-107, plan 20f E10): one Open sheet per locked file; a password that does
/// not open it shakes the sheet (the second sheet), the right one gives the file's result; Cancel skips the file. An
/// error that is not "still locked" ends the asking and is reported, never shown as a wrong password (review of M7).
@Suite("Locked inputs ask once per file")
@MainActor
struct LockedInputPromptingTests {
    enum Failure: Error, Equatable { case crashed }

    let file = URL(fileURLWithPath: "/in/Menu.pdf")

    func secrets(_ text: String) -> PasswordAnswer {
        .secrets(JobSecrets(input: JobSecret(utf8: text)), sameForAll: false)
    }

    /// The right password opens the file with `value`; any other leaves it locked.
    func opens<Value>(with password: String, _ value: Value) -> (JobSecrets) async -> LockedAttempt<Value, Failure> {
        { secrets in
            secrets.input?.withBytes { String(decoding: $0, as: UTF8.self) } == password ? .opened(value) : .stillLocked
        }
    }

    @Test func theRightPasswordGivesTheFilesResult() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("right")])
        let result = await LockedInputPrompting.unlock(
            file, prompter: prompter, near: nil, attempt: opens(with: "right", "the text"))
        #expect(result == .opened("the text"))
        #expect(prompter.asked.map(\.mode) == [.open] && prompter.asked.first?.files == ["Menu.pdf"])
    }

    @Test func aWrongPasswordAsksAgainInTheSecondSheet() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("wrong"), secrets("right")])
        let result = await LockedInputPrompting.unlock(
            file, prompter: prompter, near: nil, attempt: opens(with: "right", 7))
        #expect(result == .opened(7))
        #expect(prompter.retried == [["Menu.pdf"]])
    }

    @Test func cancelSkipsTheFile() async {
        let prompter = ProtectBatchTests.FakePrompter([.cancelled])
        var attempts = 0
        let result: LockedOutcome<String, Failure> = await LockedInputPrompting.unlock(
            file, prompter: prompter, near: nil
        ) { _ in
            attempts += 1
            return .opened("never")
        }
        #expect(result == .skipped && attempts == 0)
    }

    @Test func anErrorIsReportedAndNeverAskedAgainAsAWrongPassword() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("right"), secrets("again")])
        let result: LockedOutcome<String, Failure> = await LockedInputPrompting.unlock(
            file, prompter: prompter, near: nil
        ) { _ in .failed(.crashed) }
        #expect(result == .failed(.crashed))
        #expect(prompter.retried.isEmpty && prompter.asked.count == 1)
    }

    @Test func aCancelledJobStopsAskingAfterAWrongPassword() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("wrong"), secrets("right")])
        let task = Task { @MainActor in
            await LockedInputPrompting.unlock(self.file, prompter: prompter, near: nil) {
                _ -> LockedAttempt<String, Failure> in
                withUnsafeCurrentTask { $0?.cancel() }
                return .stillLocked
            }
        }
        #expect(await task.value == .cancelled)
        #expect(prompter.retried.isEmpty)
    }

    @Test func noWindowIsNotACancel() async {
        let prompter = ProtectBatchTests.FakePrompter([.unavailable])
        let result = await LockedInputPrompting.unlock(
            file, prompter: prompter, near: nil, attempt: opens(with: "x", 1))
        #expect(result == .unavailable)
    }

    @Test func twoLockedFilesAreAskedOneEachInDropOrder() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("a"), secrets("b")])
        let files = [URL(fileURLWithPath: "/in/a.pdf"), URL(fileURLWithPath: "/one/same.pdf")]
        let results = await LockedInputPrompting.unlockEach(files, prompter: prompter, near: nil) {
            file, secrets -> LockedAttempt<String, Failure> in
            let typed = secrets.input?.withBytes { String(decoding: $0, as: UTF8.self) }
            return typed == (file == files[0] ? "a" : "b") ? .opened(file.path) : .stillLocked
        }
        #expect(prompter.asked.map(\.files) == [["a.pdf"], ["same.pdf"]])
        #expect(results == [.opened("/in/a.pdf"), .opened("/one/same.pdf")])
    }

    @Test func noWindowStopsAskingForTheOtherFiles() async {
        let prompter = ProtectBatchTests.FakePrompter([.unavailable, secrets("b")])
        let files = [URL(fileURLWithPath: "/in/a.pdf"), URL(fileURLWithPath: "/in/b.pdf")]
        let results = await LockedInputPrompting.unlockEach(files, prompter: prompter, near: nil) {
            _, _ -> LockedAttempt<String, Failure> in .opened("never")
        }
        #expect(results == [.unavailable, .skipped])
        #expect(prompter.asked.count == 1)
    }

    /// The Open sheet asks for the file's password only: no switch to Change, and its words say it opens the file.
    @Test func theOpenSheetHasNoChangeSwitch() {
        let model = PasswordSheetModel(mode: .open, files: ["Menu.pdf"])
        #expect(model.changeSwitchLabel == nil)
        #expect(model.fields == [.password])
        #expect(model.window.title == "Open" && model.apply.label == "Open")
        #expect(model.footer == PasswordCopy.noRecovery)
    }
}

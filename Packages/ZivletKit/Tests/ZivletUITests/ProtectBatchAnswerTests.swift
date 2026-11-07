import Foundation
import Testing
import ZivletActions
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

/// Each sheet's answer is honoured for the files it was given (review of M7): a per-file sheet's switch to Change and
/// its restrictions go with that file's own job, the retry of a Change asks for Change again, the batch checkbox of the
/// retry and owner-needed sheets is obeyed, and a sheet that could not open is not a Cancel.
@Suite("LOCK · UNLOCK answers go with the files they were given")
@MainActor
struct ProtectBatchAnswerTests {
    typealias FakePrompter = ProtectBatchTests.FakePrompter
    typealias FakeSubmitter = ProtectBatchTests.FakeSubmitter

    let files = ["a.pdf", "b.pdf"].map { URL(fileURLWithPath: "/in/\($0)") }
    let restricted = PDFRestrictions(printing: .none, copying: false, editing: true)

    func unlock(_ text: String, sameForAll: Bool = true) -> PasswordAnswer {
        .secrets(JobSecrets(input: JobSecret(utf8: text)), sameForAll: sameForAll)
    }

    func change(_ current: String, to new: String, sameForAll: Bool = true) -> PasswordAnswer {
        .secrets(JobSecrets(input: JobSecret(utf8: current), newUser: JobSecret(utf8: new)), sameForAll: sameForAll)
    }

    func lock(_ new: String, restrictions: PDFRestrictions? = nil, sameForAll: Bool = true) -> PasswordAnswer {
        let owner = restrictions == nil ? nil : JobSecret(utf8: "owner")
        return .secrets(
            JobSecrets(newUser: JobSecret(utf8: new), owner: owner), sameForAll: sameForAll, restrictions: restrictions)
    }

    /// Each submitted group as "names: spec".
    func calls(_ submitter: FakeSubmitter) -> [String] {
        zip(submitter.submitted, submitter.specs).map { "\($0.0.joined(separator: ",")): \($0.1.mode)" }
    }

    func runUnlock(_ prompter: FakePrompter, _ submitter: FakeSubmitter) async -> ProtectBatchOutcome {
        await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(files, mode: .unlock, spec: ProtectSpec(mode: .unlock), near: nil)
    }

    func runLock(_ prompter: FakePrompter, _ submitter: FakeSubmitter) async -> ProtectBatchOutcome {
        await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(files, mode: .lock, spec: ProtectSpec(mode: .lock(nil)), near: nil)
    }

    @Test func unlockForTheFirstAndChangeForTheSecondChangesTheSecond() async {
        let prompter = FakePrompter([unlock("one", sameForAll: false), change("two", to: "new")])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "one", "b.pdf": "two"])
        let outcome = await runUnlock(prompter, submitter)
        #expect(calls(submitter) == ["a.pdf: unlock", "b.pdf: changePassword"])
        #expect(submitter.specs.last == ProtectSpec(mode: .changePassword, keepRestrictions: true))
        #expect(outcome.succeeded == files)
    }

    @Test func changeForTheFirstAndUnlockForTheSecondUnlocksTheSecond() async {
        let prompter = FakePrompter([change("one", to: "new", sameForAll: false), unlock("two")])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "one", "b.pdf": "two"])
        let outcome = await runUnlock(prompter, submitter)
        #expect(calls(submitter) == ["a.pdf: changePassword", "b.pdf: unlock"])
        #expect(outcome.succeeded == files)
    }

    @Test func restrictionsOnlyOnTheFirstLockStayWithTheFirst() async {
        let prompter = FakePrompter([lock("x", restrictions: restricted, sameForAll: false), lock("y")])
        let submitter = FakeSubmitter(opensWith: [:])
        let outcome = await runLock(prompter, submitter)
        #expect(submitter.specs == [ProtectSpec(mode: .lock(restricted)), ProtectSpec(mode: .lock(nil))])
        #expect(submitter.submitted == [["a.pdf"], ["b.pdf"]])
        #expect(outcome.succeeded == files)
    }

    @Test func restrictionsOnlyOnTheSecondLockGoWithTheSecond() async {
        let prompter = FakePrompter([lock("x", sameForAll: false), lock("y", restrictions: restricted)])
        let submitter = FakeSubmitter(opensWith: [:])
        let outcome = await runLock(prompter, submitter)
        #expect(submitter.specs == [ProtectSpec(mode: .lock(nil)), ProtectSpec(mode: .lock(restricted))])
        #expect(outcome.succeeded == files)
    }

    @Test func aWrongCurrentPasswordInChangeAsksForChangeAgain() async {
        let prompter = FakePrompter([change("wrong", to: "new"), change("right", to: "new")])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "right"])
        let outcome = await ProtectBatch(prompter: prompter, submitter: submitter)
            .run([files[0]], mode: .unlock, spec: ProtectSpec(mode: .unlock), near: nil)
        #expect(prompter.asked.map(\.mode) == [.unlock, .change])
        #expect(prompter.retried == [["a.pdf"]])
        #expect(submitter.specs.map(\.mode) == [.changePassword, .changePassword])
        #expect(outcome.succeeded == [files[0]] && outcome.notOpened.isEmpty)
    }

    @Test func theRetrySheetWithTheCheckboxOffAsksEachFile() async {
        let prompter = FakePrompter([unlock("bad"), unlock("one", sameForAll: false), unlock("two")])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "one", "b.pdf": "two"])
        let outcome = await runUnlock(prompter, submitter)
        #expect(prompter.retried == [["a.pdf", "b.pdf"], ["b.pdf"]])
        #expect(submitter.submitted == [["a.pdf", "b.pdf"], ["a.pdf", "b.pdf"]])
        #expect(submitter.sharedObjects == [1, 2], "the retry carries each file's own password")
        #expect(outcome.succeeded == files)
    }

    @Test func theOwnerSheetWithTheCheckboxOffAsksEachFile() async {
        let owner = { (text: String, same: Bool) in
            PasswordAnswer.secrets(JobSecrets(owner: JobSecret(utf8: text)), sameForAll: same)
        }
        let prompter = FakePrompter([unlock("user"), owner("ownerA", false), owner("ownerB", true)])
        let submitter = FakeSubmitter(
            opensWith: ["a.pdf": "user", "b.pdf": "user"], restricted: ["a.pdf", "b.pdf"],
            owners: ["a.pdf": "ownerA", "b.pdf": "ownerB"])
        let outcome = await runUnlock(prompter, submitter)
        #expect(prompter.asked.map(\.mode) == [.unlock, .ownerNeeded, .ownerNeeded])
        #expect(prompter.asked.map(\.files) == [["a.pdf", "b.pdf"], ["a.pdf", "b.pdf"], ["b.pdf"]])
        #expect(prompter.retried.isEmpty, "b.pdf gets its own owner sheet, not a wrong-password retry")
        #expect(submitter.submitted == [["a.pdf", "b.pdf"], ["a.pdf", "b.pdf"]])
        #expect(outcome.succeeded == files && outcome.notOpened.isEmpty)
    }

    @Test func aSheetThatCouldNotOpenIsNotACancel() async {
        let submitter = FakeSubmitter(opensWith: [:])
        let outcome = await runUnlock(FakePrompter([.unavailable]), submitter)
        #expect(submitter.submitted.isEmpty)
        #expect(outcome.unavailable && !outcome.cancelled)
        #expect(ProtectBatchOutcome.nothing.cancelled && !ProtectBatchOutcome.nothing.unavailable)
        #expect(outcome.refusal == .failed(ActionCard(title: "Finish the open window first")))
        #expect(ProtectBatchOutcome.nothing.refusal == nil)
    }
}

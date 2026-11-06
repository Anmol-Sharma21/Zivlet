import Foundation
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

/// One sheet per drop (17b §3.3, plan 20f E7): the same password for every file by default; the files it did not open
/// are asked again in a second sheet that lists them, and the files that opened are not redone.
@Suite("LOCK · UNLOCK batches ask once and retry only the failures")
@MainActor
struct ProtectBatchTests {
    /// Answers in order; records each request.
    final class FakePrompter: PasswordPrompting {
        var answers: [PasswordAnswer]
        var asked: [PasswordRequest] = []
        var retried: [[String]] = []

        init(_ answers: [PasswordAnswer]) { self.answers = answers }

        func ask(_ request: PasswordRequest) async -> PasswordAnswer {
            asked.append(request)
            return answers.isEmpty ? .cancelled : answers.removeFirst()
        }

        func retry(_ request: PasswordRequest, failed: [String]) async -> PasswordAnswer {
            retried.append(failed)
            return await ask(request)
        }
    }

    /// Each file opens with its own password; the owner password opens restricted ones.
    final class FakeSubmitter: ProtectSubmitting, @unchecked Sendable {
        let opensWith: [String: String]
        let restricted: Set<String>
        let owners: [String: String]
        var submitted: [[String]] = []
        var specs: [ProtectSpec] = []
        var sharedObjects: [Int] = []

        init(opensWith: [String: String], restricted: Set<String> = [], owners: [String: String] = [:]) {
            self.opensWith = opensWith
            self.restricted = restricted
            self.owners = owners
        }

        func protect(_ files: [URL], spec: ProtectSpec, secrets: [URL: JobSecrets]) async -> [URL: JobState] {
            submitted.append(files.map(\.lastPathComponent))
            specs.append(spec)
            sharedObjects.append(Set(secrets.values.compactMap(\.input).map(ObjectIdentifier.init)).count)
            var states: [URL: JobState] = [:]
            for file in files { states[file] = state(file, spec, secrets[file]) }
            return states
        }

        private func state(_ file: URL, _ spec: ProtectSpec, _ secrets: JobSecrets?) -> JobState {
            let name = file.lastPathComponent
            if case .lock = spec.mode { return .succeeded(published(name)) }
            let text = { (secret: JobSecret?) in secret?.withBytes { String(decoding: $0, as: UTF8.self) } }
            if let owner = text(secrets?.owner) {
                return owners[name] == owner ? .succeeded(published(name)) : .failed(.wrongPassword)
            }
            guard text(secrets?.input) == opensWith[name] else { return .failed(.wrongPassword) }
            return restricted.contains(name) ? .failed(.ownerPasswordNeeded) : .succeeded(published(name))
        }

        private func published(_ name: String) -> PublishedOutput {
            PublishedOutput(
                url: URL(fileURLWithPath: "/out/\(name)"), format: .pdf, byteCount: 9, fileID: 1, modified: Date())
        }
    }

    let files = ["a.pdf", "b.pdf", "c.pdf"].map { URL(fileURLWithPath: "/in/\($0)") }

    func answer(_ text: String, sameForAll: Bool = true) -> PasswordAnswer {
        .secrets(JobSecrets(input: JobSecret(utf8: text)), sameForAll: sameForAll)
    }

    @Test func aPasswordRightForTwoOfThreeAsksAgainForTheThirdOnly() async {
        let prompter = FakePrompter([answer("one"), answer("two")])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "one", "b.pdf": "one", "c.pdf": "two"])
        let outcome = await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(files, mode: .unlock, spec: ProtectSpec(mode: .unlock), near: nil)

        #expect(submitter.submitted == [["a.pdf", "b.pdf", "c.pdf"], ["c.pdf"]])
        #expect(prompter.retried == [["c.pdf"]])
        #expect(submitter.sharedObjects.first == 1, "one secret object serves the whole batch")
        #expect(outcome.succeeded.map(\.lastPathComponent) == ["a.pdf", "b.pdf", "c.pdf"])
        #expect(outcome.notOpened.isEmpty)
    }

    @Test func cancellingTheSecondSheetKeepsTheTwoAndCountsTheThird() async {
        let prompter = FakePrompter([answer("one"), .cancelled])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "one", "b.pdf": "one", "c.pdf": "two"])
        let outcome = await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(files, mode: .unlock, spec: ProtectSpec(mode: .unlock), near: nil)

        #expect(submitter.submitted.count == 1)
        #expect(outcome.succeeded.count == 2)
        #expect(outcome.notOpened.map(\.lastPathComponent) == ["c.pdf"])
        #expect(ProtectBatchOutcome.notUnlockedLine(1) == "1 file not unlocked")
        #expect(ProtectBatchOutcome.notUnlockedLine(2) == "2 files not unlocked")
    }

    @Test func withTheSwitchOffEachFileIsAskedInDropOrder() async {
        let prompter = FakePrompter([answer("one", sameForAll: false), answer("two"), answer("three")])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "one", "b.pdf": "two", "c.pdf": "three"])
        let outcome = await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(files, mode: .unlock, spec: ProtectSpec(mode: .unlock), near: nil)

        #expect(prompter.asked.map(\.files) == [["a.pdf", "b.pdf", "c.pdf"], ["b.pdf"], ["c.pdf"]])
        #expect(submitter.submitted == [["a.pdf", "b.pdf", "c.pdf"]])
        #expect(outcome.succeeded.count == 3)
    }

    @Test func lockOfThreeFilesAsksOnceAndWritesThree() async {
        let prompter = FakePrompter([.secrets(JobSecrets(newUser: JobSecret(utf8: "new")), sameForAll: true)])
        let submitter = FakeSubmitter(opensWith: [:])
        let outcome = await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(files, mode: .lock, spec: ProtectSpec(mode: .lock(nil)), near: nil)
        #expect(prompter.asked.count == 1 && submitter.submitted == [["a.pdf", "b.pdf", "c.pdf"]])
        #expect(outcome.succeeded.count == 3)
    }

    @Test func restrictionsChosenInTheSheetGoWithTheLockJobs() async {
        let restrictions = PDFRestrictions(printing: .none, copying: false, editing: true)
        let secrets = JobSecrets(newUser: JobSecret(utf8: "new"), owner: JobSecret(utf8: "owner"))
        let prompter = FakePrompter([.secrets(secrets, sameForAll: true, restrictions: restrictions)])
        let submitter = FakeSubmitter(opensWith: [:])
        _ = await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(files, mode: .lock, spec: ProtectSpec(mode: .lock(nil)), near: nil)
        #expect(submitter.specs == [ProtectSpec(mode: .lock(restrictions))])
    }

    @Test func cancellingTheFirstSheetSubmitsNothing() async {
        let submitter = FakeSubmitter(opensWith: [:])
        let outcome = await ProtectBatch(prompter: FakePrompter([.cancelled]), submitter: submitter)
            .run(files, mode: .unlock, spec: ProtectSpec(mode: .unlock), near: nil)
        #expect(submitter.submitted.isEmpty && outcome.succeeded.isEmpty && outcome.cancelled)
    }

    /// A restricted file opened by its user password asks for the owner password in the owner-needed sheet.
    @Test func aRestrictedFileAsksForItsOwnerPassword() async {
        let owner = PasswordAnswer.secrets(JobSecrets(owner: JobSecret(utf8: "owner")), sameForAll: true)
        let prompter = FakePrompter([answer("user"), owner])
        let submitter = FakeSubmitter(opensWith: ["a.pdf": "user"], restricted: ["a.pdf"], owners: ["a.pdf": "owner"])
        let outcome = await ProtectBatch(prompter: prompter, submitter: submitter)
            .run([files[0]], mode: .unlock, spec: ProtectSpec(mode: .unlock), near: nil)
        #expect(prompter.asked.map(\.mode) == [.unlock, .ownerNeeded])
        #expect(submitter.submitted == [["a.pdf"], ["a.pdf"]])
        #expect(outcome.succeeded.map(\.lastPathComponent) == ["a.pdf"])
    }
}

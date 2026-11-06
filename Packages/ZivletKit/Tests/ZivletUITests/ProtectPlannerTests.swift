import Foundation
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletRuntime

@testable import ZivletUI

/// After a drop on LOCK · UNLOCK the worker's pre-flight picks the mode (D-M7-19): none encrypted → Lock; all → Unlock
/// (Change is a mode inside it); mixed → Lock for the plain ones, the locked ones left as they are; files that only
/// have restrictions → the owner-needed sheet.
@Suite("LOCK · UNLOCK picks its sheet from the drop")
@MainActor
struct ProtectPlannerTests {
    nonisolated static let aes = PDFEncryption.standard(
        revision: 4, version: 4, streams: .aes128, strings: .aes128, files: .aes128)
    nonisolated static let plain = PDFInspection.read(PDFPreflight(pageCount: 2))
    nonisolated static let locked = PDFInspection.read(
        PDFPreflight(pageCount: 0, encryption: aes, permissions: .all, opensWithoutPassword: false))
    nonisolated static let restricted = PDFInspection.read(
        PDFPreflight(pageCount: 2, encryption: aes, permissions: [.printLowQuality], matched: .user))
    nonisolated static let damaged = PDFInspection.refused(.unsupportedInput(.pdfDamaged))

    func urls(_ count: Int) -> [URL] { (0..<count).map { URL(fileURLWithPath: "/in/\($0).pdf") } }

    func decide(_ answers: [PDFInspection]) -> ProtectPlanner.Decision {
        ProtectPlanner.decide(Array(zip(urls(answers.count), answers)))
    }

    @Test func plainFilesAreLocked() {
        #expect(decide([Self.plain, Self.plain]) == .ask(.lock, ProtectSpec(mode: .lock(nil)), urls(2)))
    }

    @Test func lockedFilesAreUnlocked() {
        #expect(decide([Self.locked, Self.locked]) == .ask(.unlock, ProtectSpec(mode: .unlock), urls(2)))
    }

    /// OS-M7-3 asks the owner; the plan locks the plain ones and lists the locked ones as left alone.
    @Test func aMixedDropLocksThePlainOnesAndLeavesTheLockedOnes() {
        #expect(decide([Self.plain, Self.locked]) == .ask(.lock, ProtectSpec(mode: .lock(nil)), urls(2)))
    }

    @Test func restrictionsOnlyFilesAskForTheOwnerPassword() {
        #expect(decide([Self.restricted]) == .ask(.ownerNeeded, ProtectSpec(mode: .unlock), urls(1)))
        #expect(decide([Self.restricted, Self.locked]) == .ask(.unlock, ProtectSpec(mode: .unlock), urls(2)))
    }

    @Test func refusedFilesGoAlongAndAreReportedByTheirJob() {
        #expect(decide([Self.plain, Self.damaged]) == .ask(.lock, ProtectSpec(mode: .lock(nil)), urls(2)))
        #expect(decide([Self.damaged]) == .report(ProtectSpec(mode: .unlock), urls(1)))
    }

    @Test func aChangeAnswerTurnsUnlockIntoChange() {
        let change = JobSecrets(input: JobSecret(utf8: "old"), newUser: JobSecret(utf8: "new"))
        #expect(
            ProtectPlanner.spec(ProtectSpec(mode: .unlock), answered: change)
                == ProtectSpec(mode: .changePassword, keepRestrictions: true))
        #expect(
            ProtectPlanner.spec(ProtectSpec(mode: .unlock), answered: JobSecrets(input: JobSecret(utf8: "x")))
                == ProtectSpec(mode: .unlock))
    }

    @Test func theInspectionCarriesNoSecret() {
        let request = WorkerRequest.inspectPDFs(urls(2))
        var dumped = ""
        dump(request, to: &dumped)
        #expect(request.secrets == nil && !dumped.contains(JobSecret.redacted))
    }

    /// The whole flow with a fake inspector, prompter and submitter: the sheet's mode, the jobs, and Cancel.
    @Test func theFlowInspectsAsksAndSubmits() async {
        let prompter = ProtectBatchTests.FakePrompter([
            .secrets(JobSecrets(newUser: JobSecret(utf8: "new")), sameForAll: true)
        ])
        let submitter = ProtectBatchTests.FakeSubmitter(opensWith: [:])
        let flow = ProtectFlow(
            inspect: { files in files.map { _ in Self.plain } }, prompter: prompter, submitter: submitter)
        _ = await flow.run(urls(3), near: nil)
        #expect(prompter.asked.map(\.mode) == [.lock])
        #expect(submitter.submitted.map(\.count) == [3])

        let cancelling = ProtectFlow(
            inspect: { files in files.map { _ in Self.locked } },
            prompter: ProtectBatchTests.FakePrompter([.cancelled]),
            submitter: submitter)
        _ = await cancelling.run(urls(2), near: nil)
        #expect(submitter.submitted.count == 1, "Cancel submits nothing")
    }
}

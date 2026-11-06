import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// What the card says for LOCK · UNLOCK (plan 20f E8): the line names what happened, the Preview note when PDFKit
/// cannot use the password, the files left as they were, and the files that stayed locked.
@Suite("Lock and unlock results in words")
struct ProtectPresentationTests {
    static func output(_ name: String) -> PublishedOutput {
        PublishedOutput(
            url: URL(fileURLWithPath: "/Users/me/\(name)"), format: .pdf, byteCount: 2_000, fileID: 1,
            modified: Date(timeIntervalSince1970: 0))
    }

    static func snapshot(
        _ mode: ProtectSpec.Mode, _ states: [(String, JobState)], notes: [PlanNote] = [], finished: Bool = true
    ) -> BatchSnapshot {
        let items = states.map { name, state in
            BatchItem(
                job: JobID(), name: name, state: state, notes: notes,
                source: ItemSource(url: URL(fileURLWithPath: "/Users/me/\(name)"), byteCount: 1_900))
        }
        return BatchSnapshot(batch: BatchID(), target: .pdf, protect: mode, items: items, isFinished: finished)
    }

    @Test(arguments: [
        (ProtectSpec.Mode.lock(nil), "Locked with AES-256", "Report Locked.pdf"),
        (
            .lock(PDFRestrictions(printing: .none, copying: false, editing: false)), "Locked with AES-256",
            "Report Locked.pdf"
        ),
        (.unlock, "Unlocked", "Report Unlocked.pdf"), (.changePassword, "Password changed", "Report Locked.pdf"),
    ])
    func eachModeSaysWhatItDid(mode: ProtectSpec.Mode, line: String, output: String) {
        let shown = BatchPresentation.make(Self.snapshot(mode, [("Report.pdf", .succeeded(Self.output(output)))]))
        #expect(shown.phase == .succeeded)
        #expect(shown.title == line)
        #expect(shown.subtitle == output)
        #expect(shown.canUndo && shown.canReveal)
    }

    @Test func severalFilesAreCounted() {
        let shown = BatchPresentation.make(
            Self.snapshot(
                .lock(nil),
                [
                    ("a.pdf", .succeeded(Self.output("a Locked.pdf"))),
                    ("b.pdf", .succeeded(Self.output("b Locked.pdf"))),
                ]))
        #expect(shown.title == "Locked with AES-256" && shown.subtitle == "2 files")
    }

    @Test func aPasswordPreviewCannotUseIsANoteOnTheCard() {
        let shown = BatchPresentation.make(
            Self.snapshot(
                .lock(nil), [("a.pdf", .succeeded(Self.output("a Locked.pdf")))], notes: [.passwordNotForPreview]))
        #expect(shown.notes == ["Preview on this Mac can't open it with this password."])
    }

    /// A mixed drop locks the plain files; the locked ones are left as they are and listed, not failed (D-M7-19).
    @Test func filesAlreadyLockedAreLeftAsTheyAreNotFailed() {
        let shown = BatchPresentation.make(
            Self.snapshot(
                .lock(nil), [("a.pdf", .succeeded(Self.output("a Locked.pdf"))), ("b.pdf", .failed(.alreadyEncrypted))])
        )
        #expect(shown.phase == .succeeded && shown.title == "Locked with AES-256")
        #expect(shown.notes == ["b.pdf: Already locked: left as it is."])
    }

    @Test func filesThatStayedLockedAreCounted() {
        let shown = BatchPresentation.make(
            Self.snapshot(
                .unlock,
                [
                    ("a.pdf", .succeeded(Self.output("a Unlocked.pdf"))),
                    ("b.pdf", .succeeded(Self.output("b Unlocked.pdf"))),
                    ("c.pdf", .failed(.wrongPassword)),
                ]))
        #expect(shown.phase == .partial && shown.title == "Unlocked 2 of 3 files")
        #expect(shown.subtitle == "1 file not unlocked")
    }

    @Test func aWrongPasswordAloneSaysSo() {
        let shown = BatchPresentation.make(Self.snapshot(.unlock, [("c.pdf", .failed(.wrongPassword))]))
        #expect(shown.phase == .failed && shown.title == "That password didn't work." && shown.subtitle == "c.pdf")
    }

    @Test(arguments: [
        (ProtectSpec.Mode.lock(nil), "Locking"), (.unlock, "Unlocking"), (.changePassword, "Changing password"),
    ])
    func theWorkingTitleNamesTheMode(mode: ProtectSpec.Mode, title: String) {
        let snapshot = Self.snapshot(mode, [("Report.pdf", .preparing)], finished: false)
        #expect(BatchPresentation.make(snapshot).title == title)
        #expect(BatchPresentation.workingTitle(snapshot) == title)
    }

    @Test func aConversionKeepsItsWords() {
        let snapshot = BatchSnapshot(
            batch: BatchID(), target: .jpg, items: [BatchItem(job: JobID(), name: "a.png", state: .preparing)],
            isFinished: false)
        #expect(BatchPresentation.workingTitle(snapshot) == "Converting to JPG")
    }
}

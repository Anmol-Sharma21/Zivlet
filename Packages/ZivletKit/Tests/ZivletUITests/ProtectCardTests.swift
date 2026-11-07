import Foundation
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletRuntime

@testable import ZivletUI

/// LOCK · UNLOCK's results near the drop and at the notch (plan 20f E8): the line, the usual buttons, the notes.
@Suite("Lock and unlock results on the card and the island")
@MainActor
struct ProtectCardTests {
    /// One Report.pdf job of `mode`, moved to `state` through the scheduler's own events.
    static func snapshot(_ mode: ProtectSpec.Mode, _ state: JobState, notes: [PlanNote] = [], finished: Bool = true)
        -> BatchSnapshot
    {
        let batch = BatchID()
        let request: JobRequest
        do {
            let input = try InputItem(url: URL(fileURLWithPath: "/Users/me/Report.pdf"), format: .pdf, byteCount: 1_900)
            request = try JobRequest(
                input: input, operation: .protect(ProtectSpec(mode: mode)),
                destination: URL(fileURLWithPath: "/Users/me"))
        } catch {
            preconditionFailure("fixture request: \(error)")
        }
        let plan = RequestPlan(requests: [request], rejections: [])
        var snapshot = BatchSnapshot(batch: batch, target: .pdf, plan: plan, protect: mode)
        snapshot = snapshot.applying(.changed(batch, request.id, state))
        if !notes.isEmpty { snapshot = snapshot.applying(.noted(batch, request.id, notes)) }
        return finished ? snapshot.applying(.finished(batch)) : snapshot
    }

    static func saved(_ name: String) -> JobState {
        .succeeded(
            PublishedOutput(
                url: URL(fileURLWithPath: "/Users/me/\(name)"), format: .pdf, byteCount: 2_100, fileID: 1,
                modified: Date(timeIntervalSince1970: 0)))
    }

    @Test func aLockedFilesCardSaysSoAndOffersTheUsualButtons() {
        let card = ResultCardModel(Self.snapshot(.lock(nil), Self.saved("Report Locked.pdf")))
        #expect(card.title == "Locked with AES-256" && card.subtitle == "Report Locked.pdf")
        #expect(card.buttons == [.undo, .reveal, .open, .copy])
        #expect(card.outputs.map(\.lastPathComponent) == ["Report Locked.pdf"])
    }

    @Test func theUnlockAndChangeCardsSayTheirLine() {
        #expect(ResultCardModel(Self.snapshot(.unlock, Self.saved("Report Unlocked.pdf"))).title == "Unlocked")
        #expect(
            ResultCardModel(Self.snapshot(.changePassword, Self.saved("Report Locked.pdf"))).title == "Password changed"
        )
    }

    @Test func theCardCarriesThePreviewNote() {
        let card = ResultCardModel(
            Self.snapshot(.lock(nil), Self.saved("Report Locked.pdf"), notes: [.passwordNotForPreview]))
        #expect(card.notes == ["Preview on this Mac can't open it with this password."])
    }

    @Test func aWrongPasswordKeepsRetry() {
        let card = ResultCardModel(Self.snapshot(.unlock, .failed(.wrongPassword)))
        #expect(card.title == "That password didn't work." && card.buttons.contains(.retry))
    }

    @Test func theIslandSaysTheLineAndTheName() {
        let line = NotchHUDCopy.saved(Self.snapshot(.unlock, Self.saved("Report Unlocked.pdf")))
        #expect(line == "Unlocked · Report Unlocked.pdf")
    }

    /// The island's opened card says what happened, as its line and the card near the drop do, not "Saved" (seen on
    /// screen in plan 20g F3).
    @Test func theIslandsCardSaysTheLineNotSaved() {
        let lock = Self.snapshot(.lock(nil), Self.saved("Report Locked.pdf"))
        let locked = NotchResultCard.lines(ResultCardModel(lock))
        #expect(locked.primary == "Locked with AES-256")
        #expect(locked.secondary == "Report Locked.pdf · 2 KB → 2 KB")
        let unlock = Self.snapshot(.unlock, Self.saved("Report Unlocked.pdf"))
        #expect(NotchResultCard.lines(ResultCardModel(unlock)).primary == "Unlocked")
    }

    @Test func theIslandAndTheCardNameTheModeWhileWorking() {
        let working = Self.snapshot(.lock(nil), .preparing, finished: false)
        #expect(NotchHUDCopy.workingTitle(working) == "Locking Report.pdf")
        #expect(NotchHUDCopy.started(working) == "Locking, Report.pdf")
        #expect(HUDCopy.title(working) == "Locking")
    }
}

import AppKit
import Foundation
import SwiftUI
import Testing
import ZivletCore

@testable import ZivletUI

/// Asking for a password from the app (P2-101, plan 20c B6, D-M7-15): the sheet opens in the one tool window near the
/// wheel, the card or the island; Apply answers with the secrets, Cancel with nothing; asks wait their turn; the
/// second sheet lists only the files that failed.
@Suite("Ask for a password in the tool window")
@MainActor
struct PasswordPrompterTests {
    typealias FakeWindow = ToolWindowCoordinatorTests.FakeWindow
    private let password = "zv-test-" + UUID().uuidString
    private let point = CGPoint(x: 400, y: 300)

    final class Rig {
        let window = FakeWindow()
        var heard: [String] = []
        lazy var coordinator = ToolWindowCoordinator(
            makeWindow: { [unowned self] in window }, contents: { _, _ in nil }, refuse: { _, _ in })
        lazy var prompter = PasswordPrompter(presenter: coordinator) { [unowned self] model in
            PasswordSheetState(model: model, announce: { [unowned self] in heard.append($0) })
        }
    }

    private func request(_ mode: PasswordMode, files: [String] = ["Report.pdf"]) -> PasswordRequest {
        PasswordRequest(mode: mode, files: files, near: point)
    }

    @Test func applyAnswersWithTheTypedSecretAndTheBatchChoice() async throws {
        let rig = Rig()
        let asked = Task { await rig.prompter.ask(request(.unlock, files: ["a.pdf", "b.pdf"])) }
        #expect(await eventually { rig.prompter.showing != nil })
        let sheet = try #require(rig.prompter.showing)
        sheet.password = password
        rig.window.onApply()
        guard case .secrets(let secrets, let sameForAll) = await asked.value else {
            Issue.record("expected secrets")
            return
        }
        #expect(secrets.input?.withBytes { Array($0) } == Array(password.utf8))
        #expect(sameForAll)
        #expect(!rig.window.isVisible)
        #expect(rig.window.shownAt == [point])
        #expect(rig.window.loaded.first?.title == "Unlock")
    }

    @Test func applyThatIsOffKeepsTheWindowOpen() async throws {
        let rig = Rig()
        let asked = Task { await rig.prompter.ask(request(.lock)) }
        #expect(await eventually { rig.prompter.showing != nil })
        rig.window.onApply()
        #expect(rig.window.isVisible)
        rig.window.pressEscape()
        #expect(await asked.value == .cancelled)
    }

    @Test func cancelAnswersWithNothingAndEmptiesTheFields() async throws {
        let rig = Rig()
        let asked = Task { await rig.prompter.ask(request(.unlock)) }
        #expect(await eventually { rig.prompter.showing != nil })
        let sheet = try #require(rig.prompter.showing)
        sheet.password = password
        rig.window.pressEscape()
        #expect(await asked.value == .cancelled)
        #expect(sheet.password.isEmpty)
        #expect(rig.prompter.showing == nil)
    }

    @Test func aSecondAskWaitsForTheFirst() async throws {
        let rig = Rig()
        let first = Task { await rig.prompter.ask(request(.unlock, files: ["first.pdf"])) }
        #expect(await eventually { rig.prompter.showing != nil })
        let second = Task { await rig.prompter.ask(request(.lock, files: ["second.pdf"])) }
        for _ in 0..<20 { await Task.yield() }
        #expect(rig.window.loaded.count == 1)
        rig.window.pressEscape()
        #expect(await first.value == .cancelled)
        #expect(await eventually { rig.window.loaded.count == 2 })
        #expect(rig.window.loaded.last?.fileLine == "second.pdf")
        rig.window.pressEscape()
        #expect(await second.value == .cancelled)
    }

    @Test func theSecondSheetListsExactlyTheFailuresAndSaysWhy() async throws {
        let rig = Rig()
        let files = ["a.pdf", "b.pdf", "c.pdf"]
        let asked = Task { await rig.prompter.retry(request(.unlock, files: files), failed: ["b.pdf", "c.pdf"]) }
        #expect(await eventually { rig.prompter.showing != nil })
        let sheet = try #require(rig.prompter.showing)
        #expect(sheet.model.retryList == ["b.pdf", "c.pdf"])
        #expect(sheet.model.failure == .wrong(attempt: 1))
        #expect(rig.heard == ["Wrong password"])
        #expect(rig.window.loaded.first?.fileLine == "2 files")
        rig.window.pressEscape()
        #expect(await asked.value == .cancelled)
    }

    @Test func anotherToolsOpenWindowIsNotTakenOver() async throws {
        let rig = Rig()
        let other = ToolWindowCoordinatorTests.FakeContent(urls: [URL(fileURLWithPath: "/tmp/in/Other.pdf")])
        rig.coordinator.present(other, near: nil)
        let answer = await rig.prompter.ask(request(.unlock))
        #expect(answer == .unavailable)
        #expect(rig.window.broughtForward == 1)
        #expect(other.cancelled == 0)
    }

    @Test func earlierCodeResultsGiveWayToTheSheet() async throws {
        let rig = Rig()
        let results = try CodeResultsTests.content(
            [CodeResultsTests.link], board: CodeResultsTests.board(), opener: CodeResultsTests.Opener())
        rig.coordinator.present(results, near: nil)
        let asked = Task { await rig.prompter.ask(request(.unlock)) }
        #expect(await eventually { rig.prompter.showing != nil })
        rig.window.pressEscape()
        #expect(await asked.value == .cancelled)
    }
}

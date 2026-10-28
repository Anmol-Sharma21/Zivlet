import AppKit
import Foundation
import SwiftUI
import TestSupport
import Testing
import ZivletCore

@testable import ZivletUI

/// A pasteboard that records what Copy asked for instead of touching the person's clipboard.
final class FakeSecretPasteboard: SecretPasteboardTarget {
    var options: NSPasteboard.ContentsOptions?
    var items: [NSPasteboardItem] = []
    var refuses = false

    func prepareForNewContents(with options: NSPasteboard.ContentsOptions) -> Int {
        self.options = options
        return 1
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        items = objects.compactMap { $0 as? NSPasteboardItem }
        return !refuses
    }
}

/// The password sheet in the tool window (P2-101, plan 20c B4): typing drives the model, Apply hands over secrets and
/// empties the fields, Copy marks the password concealed, transient and for this Mac, and the hosted sheet takes the
/// keyboard in its first field.
@Suite("The password sheet in the tool window")
@MainActor
struct PasswordSheetViewTests {
    private let password = "zv-test-" + UUID().uuidString

    private func state(_ mode: PasswordMode, files: [String] = ["Report.pdf"]) -> PasswordSheetState {
        PasswordSheetState(model: PasswordSheetModel(mode: mode, files: files), announce: { _ in })
    }

    @Test func typingDrivesTheModelAndTellsTheShell() {
        let sheet = state(.lock)
        var shells: [ToolWindowModel] = []
        sheet.modelChanged = { shells.append($0.window) }
        sheet.password = password
        #expect(sheet.model.apply.reason == "Passwords don't match")
        sheet.confirm = password
        #expect(sheet.model.apply == .enabled(label: "Lock"))
        #expect(shells.last?.apply == .enabled(label: "Lock"))
    }

    @Test func lockHandsOverTheNewPasswordAndEmptiesTheFields() {
        let sheet = state(.lock)
        sheet.password = password
        sheet.confirm = password
        let secrets = sheet.takeSecrets()
        #expect(secrets.newUser?.withBytes { Array($0) } == Array(password.utf8))
        #expect(secrets.input == nil && secrets.owner == nil)
        #expect(sheet.password.isEmpty && sheet.confirm.isEmpty && sheet.current.isEmpty)
        #expect(!sheet.model.apply.isEnabled)
    }

    @Test func unlockOwnerAndChangeFillTheirRoles() {
        let unlock = state(.unlock)
        unlock.password = password
        #expect(unlock.takeSecrets().input?.withBytes { Array($0) } == Array(password.utf8))

        let owner = state(.ownerNeeded)
        owner.password = password
        let ownerSecrets = owner.takeSecrets()
        #expect(ownerSecrets.owner?.withBytes { Array($0) } == Array(password.utf8))
        #expect(ownerSecrets.input == nil)

        let change = state(.change)
        change.current = "old-" + password
        change.password = password
        change.confirm = password
        let changed = change.takeSecrets()
        #expect(changed.input?.withBytes { Array($0) } == Array(("old-" + password).utf8))
        #expect(changed.newUser?.withBytes { Array($0) } == Array(password.utf8))
    }

    @Test func aWrongAttemptCountsEmptiesTheFieldAndIsAnnounced() {
        var heard: [String] = []
        let sheet = PasswordSheetState(
            model: PasswordSheetModel(mode: .unlock, files: ["a.pdf"]), announce: { heard.append($0) })
        sheet.password = password
        sheet.wrongAttempt()
        sheet.password = password
        sheet.wrongAttempt()
        #expect(sheet.model.failure == .wrong(attempt: 2))
        #expect(heard == ["Wrong password", "Wrong password"])
        #expect(sheet.password.isEmpty)
    }

    @Test func turningToChangeEmptiesTheFields() {
        let sheet = state(.unlock)
        sheet.password = password
        sheet.switchToChange()
        #expect(sheet.model.mode == .change)
        #expect(sheet.password.isEmpty)
    }

    @Test func revealingShowsEveryField() {
        let sheet = state(.lock)
        sheet.toggleReveal()
        #expect(sheet.model.revealed)
        sheet.toggleReveal()
        #expect(!sheet.model.revealed)
    }

    @Test func copyMarksThePasswordConcealedTransientAndForThisMac() throws {
        let board = FakeSecretPasteboard()
        let sheet = PasswordSheetState(
            model: PasswordSheetModel(mode: .lock, files: ["a.pdf"]), pasteboard: SecretPasteboard(target: board),
            announce: { _ in })
        sheet.password = password
        #expect(sheet.copyPassword())
        #expect(board.options == .currentHostOnly)
        let item = try #require(board.items.first)
        #expect(item.string(forType: .string) == password)
        #expect(item.types.contains(SecretPasteboard.concealed))
        #expect(item.types.contains(SecretPasteboard.transient))
        #expect(SecretPasteboard.concealed.rawValue == "org.nspasteboard.ConcealedType")
        #expect(SecretPasteboard.transient.rawValue == "org.nspasteboard.TransientType")
    }

    @Test func copyWithNothingTypedWritesNothing() {
        let board = FakeSecretPasteboard()
        let sheet = PasswordSheetState(
            model: PasswordSheetModel(mode: .lock, files: ["a.pdf"]), pasteboard: SecretPasteboard(target: board),
            announce: { _ in })
        #expect(!sheet.copyPassword())
        #expect(board.options == nil && board.items.isEmpty)
    }

    @Test func aRefusingPasteboardIsReported() {
        let board = FakeSecretPasteboard()
        board.refuses = true
        let sheet = PasswordSheetState(
            model: PasswordSheetModel(mode: .lock, files: ["a.pdf"]), pasteboard: SecretPasteboard(target: board),
            announce: { _ in })
        sheet.password = password
        #expect(!sheet.copyPassword())
    }

    // MARK: Hosted in the tool window

    /// The sheet in a real tool window far off every screen, key, with counters for Apply and Cancel.
    final class Hosted {
        let window = ToolWindow()
        let sheet: PasswordSheetState
        var applied = 0
        var cancelled = 0

        init(_ sheet: PasswordSheetState) {
            self.sheet = sheet
            window.onApply = { [unowned self] in applied += 1 }
            window.onCancel = { [unowned self] in cancelled += 1 }
            sheet.modelChanged = { [weak window] in window?.update($0.window) }
            window.load(sheet.model.window, content: AnyView(PasswordSheetView(state: sheet)))
            window.setFrameOrigin(CGPoint(x: -5_000, y: -5_000))
            window.makeKeyAndOrderFront(nil)
        }

        var editor: NSTextView? { window.firstResponder as? NSTextView }
        var editsASecureField: Bool { editor.map { $0.delegate is NSSecureTextField } ?? false }
    }

    @Test(.enabled(if: !ScreenSession.isLocked, Comment(rawValue: ScreenSession.lockedReason)))
    func theFirstFieldTakesTheKeyboardAsASecureField() async {
        let hosted = Hosted(state(.lock))
        defer { hosted.window.close() }
        #expect(await eventually { hosted.editsASecureField })
    }

    @Test(.enabled(if: !ScreenSession.isLocked, Comment(rawValue: ScreenSession.lockedReason)))
    func escapeInTheFieldCancels() async {
        let hosted = Hosted(state(.unlock))
        defer { hosted.window.close() }
        #expect(await eventually { hosted.editsASecureField })
        hosted.editor?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(hosted.cancelled == 1)
        #expect(!hosted.window.isVisible)
    }

    @Test(.enabled(if: !ScreenSession.isLocked, Comment(rawValue: ScreenSession.lockedReason)))
    func returnInTheFieldAppliesOnlyWhenApplyIsOn() async throws {
        let sheet = state(.unlock)
        let hosted = Hosted(sheet)
        defer { hosted.window.close() }
        #expect(await eventually { hosted.editsASecureField })
        let enter = try ToolWindowTests.key("\r", code: 36)
        _ = hosted.window.performKeyEquivalent(with: enter)
        hosted.editor?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(hosted.applied == 0)
        sheet.password = password
        hosted.editor?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(await eventually { hosted.applied == 1 })
    }

    @Test func everyControlHasAVoiceOverLabel() {
        let sheet = state(.lock, files: ["a.pdf", "b.pdf"])
        sheet.password = password
        let labels = PasswordSheetView.controlLabels(sheet.model, canSuggest: true)
        #expect(Set(labels).isSuperset(of: ["Password", "Confirm", "Show password", "Copy", "Suggest"]))
        #expect(labels.contains("Use the same password for all 2 files"))
        #expect(
            PasswordSheetView.controlLabels(sheet.model.with(revealed: true), canSuggest: false)
                .contains("Hide password"))
        #expect(
            PasswordSheetView.controlLabels(state(.unlock).model, canSuggest: true)
                .contains("Change password…"))
        #expect(PasswordSheetView.strengthLabel(.strong) == "Password strength: Strong")
    }
}

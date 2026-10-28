import AppKit
import Observation
import SwiftUI
import ZivletCore

/// The sheet's live state (P2-101, plan 20c B4): the model and the text in the fields. Typing re-judges the model and
/// tells the window (`modelChanged`); Apply takes the text as `JobSecret`s and empties the fields at once, so the
/// typed text lives only while the window is open (the `String`s themselves are freed, not zeroed: best effort,
/// D-M7-14).
@Observable
public final class PasswordSheetState {
    public private(set) var model: PasswordSheetModel
    public var password = "" { didSet { judge() } }
    public var confirm = "" { didSet { judge() } }
    public var current = "" { didSet { judge() } }
    @ObservationIgnored public var modelChanged: (PasswordSheetModel) -> Void = { _ in }
    @ObservationIgnored private let pasteboard: SecretPasteboard
    @ObservationIgnored private let suggester: (any PasswordSuggesting)?
    private var suggestFailed = false
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    public init(
        model: PasswordSheetModel, pasteboard: SecretPasteboard = SecretPasteboard(),
        suggester: (any PasswordSuggesting)? = nil,
        announce: @escaping @MainActor (String) -> Void = PasswordSheetState.postAnnouncement
    ) {
        self.model = model
        self.pasteboard = pasteboard
        self.suggester = suggester
        self.announce = announce
    }

    /// VoiceOver says `text` now.
    public static func postAnnouncement(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    /// The typed passwords in their roles (Lock: new; Unlock: input; owner-needed: owner; Change: input and new), then
    /// the fields are emptied.
    public func takeSecrets() -> JobSecrets {
        let typed = JobSecret(utf8: password)
        let secrets: JobSecrets =
            switch model.mode {
            case .lock: JobSecrets(newUser: typed)
            case .unlock: JobSecrets(input: typed)
            case .ownerNeeded: JobSecrets(owner: typed)
            case .change: JobSecrets(input: JobSecret(utf8: current), newUser: typed)
            }
        clearFields()
        return secrets
    }

    /// The password did not open the file: one more shake, VoiceOver hears it, and the field is empty for the next try.
    public func wrongAttempt() {
        password = ""
        show(model.wrongAttempt())
        if let announcement = model.announcement { announce(announcement) }
    }

    /// Unlock becomes Change in the same window (FR-96).
    public func switchToChange() {
        clearFields()
        show(model.switchedToChange())
    }

    public func toggleReveal() { show(model.with(revealed: !model.revealed)) }
    public func setSameForAll(_ on: Bool) { show(model.with(sameForAll: on)) }

    /// Shows `model` in place of the current one (the second sheet, a new state from the job).
    public func show(_ next: PasswordSheetModel) {
        model = next
        modelChanged(next)
    }

    /// Copies the new password to the pasteboard for this Mac, concealed and transient.
    @discardableResult
    public func copyPassword() -> Bool { pasteboard.copy(password) }

    /// Suggest is offered: a new password is being set, there is a generator, and it has not come back empty.
    public var canSuggest: Bool { model.setsPassword && suggester != nil && !suggestFailed }

    /// Suggest: fills the new password and its confirmation alike and reveals them; nothing made hides the button.
    public func suggest() {
        guard canSuggest else { return }
        guard let text = suggester?.suggest() else {
            suggestFailed = true
            return
        }
        password = text
        confirm = text
        show(model.with(revealed: true))
    }

    public func clearFields() {
        password = ""
        confirm = ""
        current = ""
    }

    private func judge() {
        show(model.entered(PasswordEntry(password: password, confirm: confirm, current: current)))
    }
}

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
    /// Lock's restrictions; `.none` until the person chooses some.
    public private(set) var restrictions = PDFRestrictions.none
    /// The owner password made when a restriction is first chosen, shown once and forgotten when the job takes it.
    public private(set) var ownerPassword: String?
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

    /// The restrictions Lock applies, or nil for none.
    public var chosenRestrictions: PDFRestrictions? {
        model.offersRestrictions && restrictions != .none ? restrictions : nil
    }

    /// Printing, copying and editing; the first restriction makes the owner password (D-M7-20), which then stays the
    /// same for this sheet. A generator that fails leaves the restrictions off.
    public func setRestrictions(_ chosen: PDFRestrictions) {
        guard model.offersRestrictions else { return }
        if chosen != .none, ownerPassword == nil {
            guard let made = try? OwnerPassword.make() else { return }
            ownerPassword = made
        }
        restrictions = chosen
        modelChanged(model)  // the window measures the section again
    }

    /// Copies the owner password for this Mac, concealed and transient.
    @discardableResult
    public func copyOwnerPassword() -> Bool { ownerPassword.map(pasteboard.copy) ?? false }

    /// The typed passwords in their roles (Lock: new, and the owner password with restrictions; Unlock: input;
    /// owner-needed: owner; Change: input and new), then the fields and the owner password are forgotten.
    public func takeSecrets() -> JobSecrets {
        let typed = JobSecret(utf8: password)
        let owner = chosenRestrictions == nil ? nil : ownerPassword.map(JobSecret.init(utf8:))
        let secrets: JobSecrets =
            switch model.mode {
            case .lock: JobSecrets(newUser: typed, owner: owner)
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
        guard next != model else { return }
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
        ownerPassword = nil
    }

    private func judge() {
        show(model.entered(PasswordEntry(password: password, confirm: confirm, current: current)))
    }
}

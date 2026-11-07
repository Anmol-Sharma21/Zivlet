import Foundation
import ZivletCore

/// What the sheet asks for: a new password (Lock), the file's password (Unlock), the current and a new one (Change),
/// the owner password of a file with restrictions (17a §3.2's [challenge]), or a locked file's password only so another
/// tool can read it (Open: Copy Text and Read QR, which never change the file).
public enum PasswordMode: Sendable, Equatable {
    case lock, unlock, change, ownerNeeded, open
}

/// A wrong password: each attempt shakes the field once, with no limit and no delay (17b §3.2).
public enum PasswordFailure: Sendable, Equatable {
    case wrong(attempt: Int)
}

/// The text in the fields, handed to the model only to be judged; the model keeps facts about it, never the text.
/// In Change, `password` is the new password.
public struct PasswordEntry: Sendable {
    public let password: String
    public let confirm: String
    public let current: String

    public init(password: String = "", confirm: String = "", current: String = "") {
        self.password = password
        self.confirm = confirm
        self.current = current
    }
}

/// Facts about the typed text that the sheet shows: no text, no length.
struct PasswordFacts: Sendable, Equatable {
    let hasPassword: Bool
    let hasCurrent: Bool
    let matches: Bool
    let fitsPDF: Bool
    let isASCII: Bool
    let strength: PasswordRules.Strength

    static let empty = PasswordFacts(PasswordEntry())

    init(_ entry: PasswordEntry) {
        hasPassword = !entry.password.isEmpty
        hasCurrent = !entry.current.isEmpty
        matches = PasswordRules.matches(entry.password, entry.confirm)
        fitsPDF = PasswordRules.fitsPDF(entry.password)
        isASCII = PasswordRules.isASCII(entry.password)
        strength = PasswordRules.strength(entry.password)
    }
}

/// The password sheet's state (P2-101, plan 20c B3), a value: every edit returns a new one. It drives the tool
/// window's shell (`window`) and the sheet's own content; the view owns the typed text and hands a `JobSecret` to the
/// job when Apply is pressed.
public struct PasswordSheetModel: Sendable, Equatable {
    public let mode: PasswordMode
    public let files: [String]
    public let sameForAll: Bool
    public let revealed: Bool
    public let failure: PasswordFailure?
    public let retryList: [String]
    let facts: PasswordFacts

    public init(mode: PasswordMode, files: [String]) {
        self.init(
            mode: mode, files: files, sameForAll: files.count > 1, revealed: false, failure: nil, retryList: [],
            facts: .empty)
    }

    private init(
        mode: PasswordMode, files: [String], sameForAll: Bool, revealed: Bool, failure: PasswordFailure?,
        retryList: [String], facts: PasswordFacts
    ) {
        self.mode = mode
        self.files = files
        self.sameForAll = sameForAll
        self.revealed = revealed
        self.failure = failure
        self.retryList = retryList
        self.facts = facts
    }

    private func copy(
        mode: PasswordMode? = nil, sameForAll: Bool? = nil, revealed: Bool? = nil,
        failure: PasswordFailure?? = nil, facts: PasswordFacts? = nil
    ) -> PasswordSheetModel {
        PasswordSheetModel(
            mode: mode ?? self.mode, files: files, sameForAll: sameForAll ?? self.sameForAll,
            revealed: revealed ?? self.revealed, failure: failure ?? self.failure, retryList: retryList,
            facts: facts ?? self.facts)
    }

    // MARK: Edits

    public func entered(_ entry: PasswordEntry) -> PasswordSheetModel { copy(facts: PasswordFacts(entry)) }
    public func with(sameForAll: Bool) -> PasswordSheetModel { copy(sameForAll: sameForAll) }
    public func with(revealed: Bool) -> PasswordSheetModel { copy(revealed: revealed) }

    /// One more wrong attempt: one more shake.
    public func wrongAttempt() -> PasswordSheetModel {
        let attempt: Int
        if case .wrong(let count) = failure { attempt = count + 1 } else { attempt = 1 }
        return copy(failure: .wrong(attempt: attempt))
    }

    /// The same window as Change: Current, New and Confirm (FR-96), with the fields empty again.
    public func switchedToChange() -> PasswordSheetModel { copy(mode: .change, failure: .some(nil), facts: .empty) }

    /// The second sheet (17b §3.3): only the files that did not open, fields empty, no failure yet.
    public func retry(names: [String]) -> PasswordSheetModel {
        PasswordSheetModel(
            mode: mode, files: names, sameForAll: names.count > 1, revealed: false, failure: nil, retryList: names,
            facts: .empty)
    }
}

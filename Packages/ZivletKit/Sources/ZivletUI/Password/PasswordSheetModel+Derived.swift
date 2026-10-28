import Foundation
import ZivletCore

/// What the sheet shows, derived from its state.
extension PasswordSheetModel {
    public var fileLine: String { ToolWindowModel.fileLine(names: files) }

    public var fields: [PasswordField] {
        switch mode {
        case .lock: [.password, .confirm]
        case .unlock, .ownerNeeded: [.password]
        case .change: [.current, .newPassword, .confirm]
        }
    }

    /// The words on Apply, and why it is off.
    public var apply: ApplyState {
        guard let reason = disabledReason.flatMap(DisabledReason.init) else { return .enabled(label: applyLabel) }
        return .disabled(label: applyLabel, reason: reason)
    }

    /// The strength word's value while a new password is typed (Lock and Change only).
    public var strength: PasswordRules.Strength? {
        setsPassword && facts.hasPassword ? facts.strength : nil
    }

    /// The notes under the fields: the owner password's reason, and the PDF warning for a new non-ASCII password.
    public var notes: [PasswordNote] {
        let owner: [PasswordNote] = mode == .ownerNeeded ? [.restrictionsNeedOwner] : []
        let ascii: [PasswordNote] = setsPassword && !facts.isASCII ? [.nonASCIIPDF] : []
        return owner + ascii
    }

    /// The line under a wrong password, and what VoiceOver says when it happens.
    public var errorLine: String? { failure == nil ? nil : PasswordCopy.wrong }
    public var announcement: String? { failure == nil ? nil : PasswordCopy.wrongAnnouncement }

    /// 17b §2.1's footer, where a file's password is asked for.
    public var footer: String? { asksForFilePassword ? PasswordCopy.noRecovery : nil }

    public var sameForAllLabel: String? { files.count > 1 ? PasswordCopy.sameForAll(files.count) : nil }
    /// Unlock may turn into Change, but not in the second sheet, which only retries the files that failed.
    public var changeSwitchLabel: String? { mode == .unlock && retryList.isEmpty ? PasswordCopy.changeSwitch : nil }

    /// Change's three fields carry their names above them: once typed, the placeholders are gone and three rows of
    /// dots would look alike.
    public var labelsFields: Bool { mode == .change }
    public var retryTitle: String? { retryList.isEmpty ? nil : PasswordCopy.retryTitle }

    /// The shell's header and Apply.
    public var window: ToolWindowModel {
        ToolWindowModel(symbol: symbol, title: title, fileLine: fileLine, apply: apply)
    }

    /// A new password is being set (Lock, Change).
    public var setsPassword: Bool { mode == .lock || mode == .change }
    private var asksForFilePassword: Bool { mode == .unlock || mode == .ownerNeeded }

    private var disabledReason: String? {
        if mode == .change, !facts.hasCurrent { return PasswordCopy.typeCurrent }
        guard facts.hasPassword else { return PasswordCopy.typePassword }
        guard setsPassword else { return nil }
        guard facts.fitsPDF else { return PasswordCopy.tooLong }
        return facts.matches ? nil : PasswordCopy.mismatch
    }

    private var applyLabel: String {
        switch mode {
        case .lock: "Lock"
        case .unlock, .ownerNeeded: "Unlock"
        case .change: "Change"
        }
    }

    private var title: String {
        mode == .change ? "Change password" : applyLabel
    }

    private var symbol: String {
        switch mode {
        case .lock: "lock"
        case .unlock, .ownerNeeded: "lock.open"
        case .change: "lock.rotation"
        }
    }
}

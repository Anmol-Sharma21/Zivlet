import Foundation
import ZivletCore

/// A one-line note under the password fields (P2-101's per-family notes): the PDF non-English-letters warning
/// (OWN-PDF-1) and why an owner password is asked for. ZIP and Office notes come with their rows.
public enum PasswordNote: Sendable, Equatable, CaseIterable {
    case nonASCIIPDF
    case restrictionsNeedOwner

    public var text: String {
        switch self {
        case .nonASCIIPDF: PasswordCopy.nonASCIIPDF
        case .restrictionsNeedOwner: PasswordCopy.restrictionsNeedOwner
        }
    }

    public var symbol: String {
        switch self {
        case .nonASCIIPDF: "exclamationmark.triangle"
        case .restrictionsNeedOwner: "info.circle"
        }
    }
}

/// One field of the sheet, in the order shown.
public enum PasswordField: Sendable, Equatable, CaseIterable {
    case current, password, newPassword, confirm

    public var label: String {
        switch self {
        case .current: PasswordCopy.current
        case .password: PasswordCopy.password
        case .newPassword: PasswordCopy.newPassword
        case .confirm: PasswordCopy.confirm
        }
    }
}

/// The sheet's words (plan 20c's string list; 17b §2.1 and §3.5, 17a §3.1 where quoted).
public enum PasswordCopy {
    public static let password = "Password"
    public static let confirm = "Confirm"
    public static let current = "Current password"
    public static let newPassword = "New password"
    public static let show = "Show password"
    public static let hide = "Hide password"
    public static let suggest = "Suggest"
    public static let copy = "Copy"
    public static let typePassword = "Type a password"
    public static let typeCurrent = "Type the current password"
    public static let mismatch = "Passwords don't match"
    public static let tooLong = "Use \(PasswordRules.pdfByteLimit) bytes or fewer"
    public static let wrong = "That password didn't work."
    public static let wrongAnnouncement = "Wrong password"
    public static let noRecovery =
        "Zivlet can't recover forgotten passwords. Try the password again, or ask the person who sent the file."
    public static let nonASCIIPDF = "Preview on Mac can't open PDFs whose password uses non-English letters."
    public static let restrictionsNeedOwner = "This PDF has restrictions. Type its owner password to remove them."
    public static let changeSwitch = "Change password…"
    public static let retryTitle = "These didn't open:"
    // Lock's restrictions (17a §3.1).
    public static let printing = "Printing"
    public static let printingChoices = ["None", "Low quality", "Full"]
    public static let allowCopying = "Allow copying"
    public static let allowEditing = "Allow editing"
    public static let ownerShownOnce = "Owner password — shown once"
    public static let notSecurity = "Restrictions are honoured by most apps but are not security."
    public static let copyOwner = "Copy owner password"

    public static func sameForAll(_ count: Int) -> String { "Use the same password for all \(count) files" }

    public static func strength(_ strength: PasswordRules.Strength) -> String {
        switch strength {
        case .weak: "Weak"
        case .fair: "Fair"
        case .strong: "Strong"
        }
    }
}

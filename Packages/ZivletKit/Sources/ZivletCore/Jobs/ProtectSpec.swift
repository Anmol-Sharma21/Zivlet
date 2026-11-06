/// What a locked PDF may still do without its owner password (17a §3.1, P2-106). Printing, copying and editing are
/// the three choices of the Lock sheet; the engine maps them onto the /P bits.
public struct PDFRestrictions: Sendable, Hashable, Codable {
    public enum Printing: String, Sendable, Hashable, Codable {
        case none, low, full
    }

    public let printing: Printing
    /// Copying text and images (accessibility stays on either way).
    public let copying: Bool
    /// Changing pages, annotating, filling forms and assembling.
    public let editing: Bool

    public init(printing: Printing, copying: Bool, editing: Bool) {
        self.printing = printing
        self.copying = copying
        self.editing = editing
    }

    /// Everything allowed: the same as no restrictions.
    public static let none = PDFRestrictions(printing: .full, copying: true, editing: true)
}

/// A LOCK · UNLOCK job (plan 20f E2, D-M7-19). It holds no password: a job's passwords travel beside it, in its own
/// requests only (D-M7-14), so a request can be logged, recorded or retried without one.
public struct ProtectSpec: Sendable, Hashable, Codable {
    public enum Mode: Sendable, Hashable, Codable {
        /// AES-256 with the typed password; restrictions add a separate owner password (D-M7-20).
        case lock(PDFRestrictions?)
        case unlock
        /// A new user password; the owner password and restrictions stay when they were known (D-M7-22).
        case changePassword

        /// The wire names: no key may read like a password field (P2-102).
        private enum CodingKeys: String, CodingKey {
            case lock, unlock
            case changePassword = "change"
        }
    }

    public let mode: Mode
    /// Change keeps the input's restrictions and owner password (the typed current password was the owner one).
    public let keepRestrictions: Bool

    public init(mode: Mode, keepRestrictions: Bool = false) {
        self.mode = mode
        self.keepRestrictions = keepRestrictions
    }
}

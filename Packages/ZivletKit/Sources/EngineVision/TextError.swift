/// Why text could not be read (P2-103, P2-104). Codable so it crosses from the worker; carries no user copy.
public enum TextError: Error, Sendable, Equatable, Codable {
    case cancelled
    /// Both Vision requests failed; the detail is Vision's own description, for the log only.
    case recognitionFailed(String)
}

/// Why a format registry or conversion catalog table was refused.
public enum CatalogError: Error, Equatable, Sendable {
    /// A registry must hold every `FormatID`, so `FormatRegistry.format(_:)` is total.
    case missingFormat(FormatID)
    case duplicateFormat(FormatID)
    case selfTarget(FormatID)
    case duplicateRow(FormatID)
    case duplicateTarget(FormatID, FormatID)
}

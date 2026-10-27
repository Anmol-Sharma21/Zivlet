/// The "Text recognition" setting (D-M6-14). Raw values are stable for the settings store.
public enum TextLanguageChoice: String, Codable, Sendable, CaseIterable {
    /// Hindi then English when the person's languages or keyboards include Hindi or Marathi, else English (P2-103).
    case matchMine
    case hindiAndEnglish
    case english
}

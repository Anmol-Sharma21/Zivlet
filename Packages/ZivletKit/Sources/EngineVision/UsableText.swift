/// Whether a PDF text layer can be used as it is (17a §3.8): at least 20 printable characters and fewer than 5 %
/// replacement characters (U+FFFD), which mark glyphs the PDF could not map to text.
public enum UsableText {
    public static let minimumPrintable = 20
    public static let maximumReplacementShare = 0.05

    public static func isUsable(_ text: String) -> Bool {
        let printable = text.unicodeScalars.filter {
            !$0.properties.isWhitespace && $0.properties.generalCategory != .control
        }
        guard printable.count >= minimumPrintable else { return false }
        let replacements = printable.filter { $0 == "\u{FFFD}" }.count
        return Double(replacements) / Double(printable.count) < maximumReplacementShare
    }
}

/// The card's script line (plan 18d D6). Devanagari is called Hindi and Latin is called English: a Marathi or a
/// French reader sees the same words, a known simplification of this first version.
public enum ScriptSummary {
    public static func line(_ scripts: Set<Script>) -> String {
        let named = [(Script.devanagari, "Hindi"), (.latin, "English")].filter { scripts.contains($0.0) }.map(\.1)
        let other = scripts.contains(.other)
        switch (named.count, other) {
        case (0, false): return ""
        case (0, true): return "Other scripts"
        case (_, false): return named.joined(separator: " and ")
        case (_, true): return named.joined(separator: ", ") + " and other scripts"
        }
    }
}

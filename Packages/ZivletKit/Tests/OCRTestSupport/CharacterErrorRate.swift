import Foundation

/// Character error rate (D-M6-12): the Levenshtein distance over Unicode scalars divided by the reference's scalar
/// count, after NFC and collapsing every whitespace run to one space (leading and trailing runs dropped).
public enum CharacterErrorRate {
    public static func cer(reference: String, hypothesis: String) -> Double {
        let truth = Array(normalized(reference).unicodeScalars)
        let guess = Array(normalized(hypothesis).unicodeScalars)
        guard !truth.isEmpty else { return guess.isEmpty ? 0 : 1 }
        return Double(distance(truth, guess)) / Double(truth.count)
    }

    /// NFC, then whitespace and newline runs as one space, trimmed.
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// Edit distance with unit costs, two rows of memory.
    static func distance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, right) in b.enumerated() {
                let substitution = previous[j] + (left == right ? 0 : 1)
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, substitution)
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// The P2-104 check: text that has Devanagari must come back with Devanagari.
public enum Devanagari {
    public static let block: ClosedRange<UInt32> = 0x0900...0x097F

    public static func contains(_ text: String) -> Bool {
        text.unicodeScalars.contains { block.contains($0.value) }
    }
}

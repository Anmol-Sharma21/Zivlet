import Foundation

extension OutputNamer {
    /// First free rendering of `name`: `name`, `name 2`, `name 3`, … (cap 9,999, 03a §4.3).
    public static func nextFree(
        _ name: OutputName, existing: Set<String>,
        caseInsensitive: Bool
    ) throws(NamingError) -> String {
        let taken = Set(existing.map { key($0, caseInsensitive: caseInsensitive) })
        let first = name.rendered()
        if !taken.contains(key(first, caseInsensitive: caseInsensitive)) { return first }
        for counter in 2...maxCandidates {
            let candidate = name.rendered(counter: counter)
            if !taken.contains(key(candidate, caseInsensitive: caseInsensitive)) { return candidate }
        }
        throw .noFreeName(first)
    }

    static func key(_ name: String, caseInsensitive: Bool) -> String {
        let nfc = name.precomposedStringWithCanonicalMapping
        return caseInsensitive ? nfc.lowercased() : nfc
    }
}

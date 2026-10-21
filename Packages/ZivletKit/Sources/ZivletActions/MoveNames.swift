import Foundation
import ZivletCore

/// Names for a moved item that collides (03b §7 row 4, the same steps as `OutputNamer`): `a.txt`, `a 2.txt`, …;
/// a folder keeps its whole name (`My.Folder 2`); a package or file keeps its extension, compound archive
/// extensions as one unit (`b 2.tar.gz`). Unlike output names, the person's name is kept exactly as it was.
nonisolated public enum MoveNames {
    public static let maxCandidates = OutputNamer.maxCandidates
    static let maxBytes = 255

    /// The name for `counter` (nil or 1 = unchanged), truncated grapheme-safely to 255 UTF-8 bytes.
    public static func candidate(_ name: String, counter: Int?, kind: MoveItem.Kind) -> String {
        guard let counter, counter > 1 else { return name }
        let stem = kind == .folder ? name : OutputNamer().baseName(of: name)
        let tail = " \(counter)" + name.dropFirst(stem.count)
        var kept = stem
        while !kept.isEmpty, (kept + tail).utf8.count > maxBytes { kept.removeLast() }
        return kept + tail
    }

    /// Case- and normalisation-insensitive key: APFS and HFS+ volumes are case-insensitive by default, and
    /// treating a case-sensitive volume the same way only ever picks a free name a step early.
    static func key(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
}

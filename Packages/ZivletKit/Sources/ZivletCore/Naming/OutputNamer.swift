import Foundation

public enum NamingError: Error, Equatable, Sendable {
    /// Every candidate up to `OutputNamer.maxCandidates` is taken; carries the first rendering.
    case noFreeName(String)
    /// The extension is not lower-case ASCII letters and digits (dot-separated, at most 16 bytes).
    case invalidExtension(String)
}

public enum MetadataNaming: Sendable, Equatable { case removeAll, edit }

public enum ChannelNaming: String, Sendable, Equatable {
    case mono = "Mono"
    case stereo = "Stereo"
}

/// Pure output naming (P0-16, 03a §4.4): base names, conversions, folders and folder items.
public struct OutputNamer: Sendable {
    public static let maxCandidates = 9_999
    static let compoundExtensions = ["tar.gz", "tgz", "tar.xz", "tar.bz2", "tar.zst"]
    static let minimumPadWidth = 3

    let registry: FormatRegistry
    let tools: ToolCatalog

    public init(registry: FormatRegistry = .standard, tools: ToolCatalog = .standard) {
        self.registry = registry
        self.tools = tools
    }

    /// The file name without its extension; a compound archive extension is stripped as one unit (03a §4.4).
    public func baseName(of fileName: String) -> String {
        let lowered = fileName.lowercased()
        for compound in Self.compoundExtensions {
            let suffix = "." + compound
            if lowered.count > suffix.count, lowered.hasSuffix(suffix) {
                return String(fileName.dropLast(suffix.count))
            }
        }
        return FileNameParts(fileName).stem
    }

    /// `<base>.<canonical extension of target>` (03a §4.4).
    public func conversion(source fileName: String, target: FormatID) -> OutputName {
        OutputName(stem: baseName(of: fileName), validExtension: registry.format(target).canonicalExtension)
    }

    /// Folder for a multi-page conversion: `<base> <LABEL> Pages` (03a §4.4).
    public func pagesFolder(source fileName: String, target: FormatID) -> OutputName {
        OutputName(stem: "\(baseName(of: fileName)) \(registry.format(target).wheelLabel) Pages", validExtension: nil)
    }

    /// One item inside an output folder: `Page 001.png` (03a §4.4). The prefix is sanitised like a stem.
    public func folderItem(prefix: String, index: Int, count: Int, ext: String) throws(NamingError) -> String {
        let stem = FileNameRules.safeStem(prefix) + " " + Self.padded(index, count: count)
        return try OutputName(stem: stem, ext: ext).rendered()
    }

    /// One video snapshot inside its folder: `Frame 001 - 12.345s.png`.
    public func snapshotItem(index: Int, count: Int, seconds: Double) -> String {
        "Frame \(Self.padded(index, count: count)) - \(String(format: "%.3f", seconds))s.png"
    }

    /// `index` zero-padded to `max(3, digits(count))`.
    static func padded(_ index: Int, count: Int) -> String {
        let width = max(minimumPadWidth, String(count).count)
        let digits = String(index)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

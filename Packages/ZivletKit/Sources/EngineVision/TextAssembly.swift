import Foundation

/// The pages read from one input file, named by its display name.
public struct FileText: Codable, Sendable, Equatable {
    public let name: String
    public let pages: [RecognizedPage]

    public init(name: String, pages: [RecognizedPage]) {
        self.name = name
        self.pages = pages
    }
}

/// One input's own text, as its `.txt` would hold it (empty when nothing was found).
public struct FileTextResult: Codable, Sendable, Equatable {
    public let name: String
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }

    public var isEmpty: Bool { text.isEmpty }
}

/// An input whose text could not be read, by its display name and why (P2-104): the rest of the drop is kept.
public struct SkippedFile: Codable, Sendable, Equatable {
    public let name: String
    public let error: TextError

    public init(name: String, error: TextError) {
        self.name = name
        self.error = error
    }
}

/// The result of one Copy Text job (P2-104). It lives in memory only and is never logged or stored (D14).
public struct RecognizedText: Codable, Sendable, Equatable {
    public let text: String
    /// Characters of the files' own text, line breaks and name lines not counted.
    public let characterCount: Int
    public let scripts: Set<Script>
    /// The first three non-empty lines, each at most 80 characters.
    public let preview: [String]
    /// Every input in order, with its own text (empty for a skipped one).
    public let perFile: [FileTextResult]
    /// The inputs that could not be read, in drop order.
    public let skipped: [SkippedFile]

    public var isEmpty: Bool { text.isEmpty }
}

/// Builds the copied text (P2-104): one file's pages joined by a blank line; several files each headed `— name —`
/// and separated by a blank line, files without text left out; LF only, no trailing spaces, one final newline.
public enum TextAssembly {
    public static let previewLines = 3
    public static let previewWidth = 80

    /// `files` holds every input in drop order (a skipped one with no pages), so `perFile` lines up with the inputs.
    public static func combine(_ files: [FileText], skipped: [SkippedFile] = []) -> RecognizedText {
        let perFile = files.map { FileTextResult(name: $0.name, text: body(of: $0.pages)) }
        let found = perFile.filter { !$0.isEmpty }
        let text: String
        if files.count == 1 {
            text = found.first?.text ?? ""
        } else {
            text = found.map { "— \($0.name) —\n" + $0.text }.joined(separator: "\n")
        }
        let ownText = found.map(\.text).joined()
        return RecognizedText(
            text: text, characterCount: ownText.filter { $0 != "\n" }.count,
            scripts: RecognizedPage(text: ownText).scripts, preview: preview(found.map(\.text).joined(separator: "\n")),
            perFile: perFile, skipped: skipped)
    }

    /// `result` with each locked file's own one-file result in its place, keyed by the file's position in the drop
    /// (plan 20f E10; never by name, as two dropped files may share one): the text is put together again in the drop's
    /// order, and the replaced files' skips give way to theirs.
    public static func merge(_ result: RecognizedText, replacing: [Int: RecognizedText]) -> RecognizedText {
        guard !replacing.isEmpty else { return result }
        let files = result.perFile.enumerated().map { index, file in
            let text = replacing[index]?.perFile.first?.text ?? file.text
            return FileText(name: file.name, pages: text.isEmpty ? [] : [RecognizedPage(text: text)])
        }
        let original = skippedInputs(result)
        let skipped = result.perFile.indices.flatMap { index in
            replacing[index]?.skipped ?? original.filter { $0.index == index }.map(\.file)
        }
        return combine(files, skipped: skipped)
    }

    /// Each skipped file with its position in the drop. Skips and inputs are both in drop order, so the n-th skip of a
    /// name is the n-th input of that name without text.
    public static func skippedInputs(_ result: RecognizedText) -> [(index: Int, file: SkippedFile)] {
        var used: Set<Int> = []
        return result.skipped.compactMap { skip in
            let index = result.perFile.indices.first { index in
                !used.contains(index) && result.perFile[index].name == skip.name && result.perFile[index].isEmpty
            }
            guard let index else { return nil }
            used.insert(index)
            return (index, skip)
        }
    }

    /// The non-empty pages, cleaned and joined by a blank line, with one final newline; empty when none has text.
    static func body(of pages: [RecognizedPage]) -> String {
        let cleaned = pages.map { clean($0.text) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? "" : cleaned.joined(separator: "\n\n") + "\n"
    }

    /// LF line breaks, trailing spaces and tabs removed, blank lines at the ends dropped.
    static func clean(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
        }
        let trimmedStart = lines.drop(while: \.isEmpty)
        return Array(trimmedStart.reversed().drop(while: \.isEmpty).reversed()).joined(separator: "\n")
    }

    static func preview(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init)
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .prefix(previewLines)
            .map { $0.count > previewWidth ? String($0.prefix(previewWidth - 1)) + "…" : $0 }
    }
}

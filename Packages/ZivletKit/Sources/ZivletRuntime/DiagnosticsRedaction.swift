import Foundation

/// Removes folder names from diagnostics text (P1-48, NFR-6): every absolute or `~/` path keeps only its last
/// component, as `…/<name>` or, under the home folder, `~/…/<name>`. A path starts at `/` or `~/` after the start of
/// a line, white space, a quote, a bracket, `=` or `:`, and runs to its last `/` on that line, so a folder name with
/// spaces is removed too; when two paths share a line the text between them may go with the first, which only
/// removes more. JSON's escaped slashes (`\/`) are read as slashes first.
public enum DiagnosticsRedaction {
    static let pattern = try? NSRegularExpression(
        pattern: #"(?<=^|[\s"'(\[<=:])~?/(?:[^/\n]*/)+"#, options: [.anchorsMatchLines])

    public static func redact(_ text: String, home: String) -> String {
        let plain = text.replacingOccurrences(of: #"\/"#, with: "/")
        guard let pattern else { return "(diagnostics text withheld: the redaction pattern did not compile)" }
        let source = plain as NSString
        let homePrefix = home.hasSuffix("/") ? home : home + "/"
        var result = ""
        var cursor = 0
        for match in pattern.matches(in: plain, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let folders = source.substring(with: match.range)
            result += folders.hasPrefix("~/") || folders.hasPrefix(homePrefix) ? "~/…/" : "…/"
            cursor = match.range.location + match.range.length
        }
        return result + source.substring(from: cursor)
    }
}

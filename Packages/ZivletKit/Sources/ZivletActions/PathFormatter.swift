import Foundation

/// Copy Path text (03b §7 row 5): one POSIX path per line, or, with ⌥, each path single-quoted for a POSIX shell
/// and separated by spaces. Inside single quotes every byte is literal except `'`, written as `'\''`.
public enum PathFormatter {
    public static func lines(_ urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    public static func shell(_ urls: [URL]) -> String {
        urls.map { quoted($0.path) }.joined(separator: " ")
    }

    static func quoted(_ path: String) -> String {
        "'" + path.replacing("'", with: #"'\''"#) + "'"
    }
}

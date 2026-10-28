import Foundation

/// Which code payloads Read QR may open (P2-51 "Open only for http(s), full URL shown, never auto-opened", D-M7-13):
/// an `http` or `https` URL with a host, exactly as written (no white space around or inside it). Everything else,
/// `javascript:`, `file:`, `mailto:`, `ftp:` and plain text included, is only shown and copied.
nonisolated public enum CodeLink {
    static let webSchemes: Set<String> = ["http", "https"]

    public static func webURL(_ payload: String) -> URL? {
        guard !payload.contains(where: \.isWhitespace), let url = URL(string: payload),
            let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme), let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    /// A link of another kind (a scheme and something after it): its row says it is not a web link, so a missing
    /// Open is explained.
    public static func isOtherLink(_ payload: String) -> Bool {
        guard webURL(payload) == nil, !payload.contains(where: \.isWhitespace), let url = URL(string: payload),
            let scheme = url.scheme, !scheme.isEmpty
        else { return false }
        return payload.count > scheme.count + 1
    }
}

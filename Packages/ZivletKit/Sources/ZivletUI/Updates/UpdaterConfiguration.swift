import Foundation

/// Whether this build may start Sparkle (P1-53, D-M4-11). The feed URL and the EdDSA public key come from the app's
/// Info.plist (`SUFeedURL`, `SUPublicEDKey`, set from the xcconfig). Until the owner sets a real feed and key (owner
/// steps O-2, O-3) the updater is not started, so nothing in Zivlet can reach a network.
public enum UpdaterConfiguration: Sendable, Equatable {
    case enabled
    case disabled(Reason)

    public enum Reason: String, Sendable, Equatable {
        /// The feed is missing, not a URL or has no host (an xcconfig cuts `https://…` at `//` unless escaped).
        case invalidFeed
        /// The feed is not `https://`.
        case insecureFeed
        /// The feed's host ends in `.invalid` (RFC 2606), the placeholder used before the owner's domain exists.
        case placeholderFeed
        case missingKey
        /// Not 44 base64 characters for a 32-byte Ed25519 key.
        case malformedKey
    }

    static let placeholderSuffix = ".invalid"
    static let keyLength = 44
    static let keyBytes = 32

    public var startsUpdater: Bool { self == .enabled }

    public static func validate(feedURL: String, publicKey: String) -> UpdaterConfiguration {
        if let reason = feedProblem(feedURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return .disabled(reason)
        }
        if let reason = keyProblem(publicKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return .disabled(reason)
        }
        return .enabled
    }

    /// Reads `SUFeedURL` and `SUPublicEDKey` from a bundle's Info.plist.
    public static func from(infoDictionary: [String: Any]) -> UpdaterConfiguration {
        validate(
            feedURL: infoDictionary["SUFeedURL"] as? String ?? "",
            publicKey: infoDictionary["SUPublicEDKey"] as? String ?? "")
    }

    private static func feedProblem(_ feed: String) -> Reason? {
        guard let components = URLComponents(string: feed), let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(), !host.isEmpty
        else { return .invalidFeed }
        guard scheme == "https" else { return .insecureFeed }
        return host.hasSuffix(placeholderSuffix) ? .placeholderFeed : nil
    }

    private static func keyProblem(_ key: String) -> Reason? {
        if key.isEmpty { return .missingKey }
        guard key.count == keyLength, let bytes = Data(base64Encoded: key), bytes.count == keyBytes else {
            return .malformedKey
        }
        return nil
    }
}

import Darwin
import Foundation
import ZivletCore

/// A dropped item an action will not touch, and why.
public struct RejectedItem: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// Not a `file:` URL (a web link, a promise that never arrived).
        case notLocal
        /// A file URL with nothing at its path any more.
        case missing

        public var userMessage: String {
            switch self {
            case .notLocal: "Not stored on this Mac."
            case .missing: "No longer there."
            }
        }
    }

    public let url: URL
    public let reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }
}

/// One action on the dropped items, validated at the boundary (03b §7 "Non-file URLs"): only `file:` URLs whose
/// path exists (`lstat`, so a dangling symlink still counts) are kept, standardized and de-duplicated in drop order.
/// Everything else is listed in `rejected` so the result card can name it.
public struct ActionRequest: Sendable, Equatable {
    public let action: ActionID
    public let items: [URL]
    public let rejected: [RejectedItem]
    /// ⌥ was down when the items were released (Copy Path quotes for the shell).
    public let optionHeld: Bool

    public init(action: ActionID, urls: [URL], optionHeld: Bool) throws(ActionError) {
        var items: [URL] = []
        var seen: Set<String> = []
        var rejected: [RejectedItem] = []
        for url in urls {
            guard url.isFileURL else {
                rejected.append(RejectedItem(url: url, reason: .notLocal))
                continue
            }
            let standard = url.standardizedFileURL
            guard Self.exists(standard) else {
                rejected.append(RejectedItem(url: url, reason: .missing))
                continue
            }
            if seen.insert(standard.path).inserted { items.append(standard) }
        }
        guard !items.isEmpty else { throw .nothingLocal(action) }
        self.action = action
        self.items = items
        self.rejected = rejected
        self.optionHeld = optionHeld
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}

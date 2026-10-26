import Foundation

/// What a bulk action works on (P2-142, 17e §2.3): the selection, or every item when nothing is selected, in the
/// box's order. Items that cannot be used now (missing, in the Trash, on a volume that is not connected) are left
/// out and named, one sentence each, for the action card. Pure.
public struct BulkTargets: Sendable, Equatable {
    /// Where the usable items are now: the resolved path, or the last known one before the box was resolved.
    public let urls: [URL]
    /// The usable items' ids, in the same order as `urls`.
    public let ids: [UUID]
    /// One line per item left out ("photo.heic is missing.").
    public let failures: [String]

    public init(urls: [URL], ids: [UUID], failures: [String]) {
        self.urls = urls
        self.ids = ids
        self.failures = failures
    }

    /// Nothing usable to act on.
    public var isEmpty: Bool { urls.isEmpty }

    /// `statuses` holds what the last resolution said; an item without a status counts as present at its last known
    /// path. Ids the box does not hold are ignored.
    public static func resolve(selection: Set<UUID>, in shelf: Shelf, statuses: [UUID: ItemStatus]) -> BulkTargets {
        let chosen = selection.isEmpty ? shelf.items : shelf.items.filter { selection.contains($0.id) }
        var urls: [URL] = []
        var ids: [UUID] = []
        var failures: [String] = []
        for item in chosen {
            let status = statuses[item.id] ?? .present(path: item.lastKnownPath)
            if case .present(let path) = status {
                urls.append(URL(filePath: path))
                ids.append(item.id)
            } else if let failure = failure(item.displayName, status) {
                failures.append(failure)
            }
        }
        return BulkTargets(urls: urls, ids: ids, failures: failures)
    }

    /// Why one item cannot take part, in Zivlet's words; nil for a present item.
    public static func failure(_ name: String, _ status: ItemStatus) -> String? {
        switch status {
        case .present: nil
        case .missing: "\(name) is missing."
        case .inTrash: "\(name) is in the Trash."
        case .volumeOffline(let volume): "\(name) is on \(volume), which isn't connected."
        }
    }
}

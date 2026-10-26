import Foundation

@testable import ZivletShelfCore

extension Date {
    /// Fixed instants so tests never read the clock.
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let t1 = Date.t0.addingTimeInterval(60)
}

/// Small, valid values for the shelf tests. Bookmarks are one byte: the pure tests never resolve them.
enum ShelfFixtures {
    static func item(
        _ name: String, size: Int64? = 1, bookmark: Data = Data([1]), path: String? = nil,
        ownership: ShelfItem.Ownership = .reference, identity: FileIdentity? = nil, addedAt: Date = .t0
    ) throws -> ShelfItem {
        try ShelfItem(
            bookmark: bookmark, lastKnownPath: path ?? "/x/\(name)", displayName: name, byteCount: size,
            addedAt: addedAt, ownership: ownership, identity: identity)
    }
}

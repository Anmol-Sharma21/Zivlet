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

extension ShelfFixtures {
    /// A box holding one item per name, each at its own path.
    static func shelf(names: [String], name: String = "Box") throws -> Shelf {
        let items = try names.map { try item($0) }
        return try Shelf.empty(name: name).adding(items, cap: ShelfLibrary.maxItemsPerBox).0
    }

    /// Two boxes, "Box" (two items) and "Box 2" (one item, current).
    static func libraryWithTwoBoxes() throws -> ShelfLibrary {
        let lib = try ShelfLibrary().adding([item("a"), item("b", size: nil)], to: .current, now: .t0).0
        return try lib.adding([item("c", identity: FileIdentity(volumeUUID: "V", fileID: 3))], to: .newBox, now: .t1)
            .0
    }
}

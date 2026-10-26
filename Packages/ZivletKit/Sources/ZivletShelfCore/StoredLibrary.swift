import Foundation
import ZivletCore

/// `boxes.json` as written: `{ "schema": 1, "boxes": [...], "current": "<uuid>" }`.
struct StoredLibrary: Encodable {
    let schema: Int
    let boxes: [Shelf]
    let current: UUID?
}

/// The first thing read from a file: only its schema, so a newer file is recognised before its boxes are read.
struct StoredHeader: Decodable {
    let schema: Int
}

/// `boxes.json` as read, leniently: a box or item that does not pass validation becomes nil and is counted, so
/// one bad entry never empties the whole library.
struct LenientLibrary: Decodable {
    let boxes: [Lenient<LenientBox>]
    let current: UUID?

    /// The valid boxes under the caps, and how many boxes and items were dropped on the way.
    func library() -> (library: ShelfLibrary, dropped: Int) {
        var dropped = 0
        var shelves: [Shelf] = []
        for entry in boxes {
            guard let (shelf, droppedItems) = entry.value?.shelf(), shelves.count < ShelfLibrary.maxBoxes,
                !shelves.contains(where: { $0.id == shelf.id })
            else {
                dropped += 1
                continue
            }
            shelves.append(shelf)
            dropped += droppedItems
        }
        return (ShelfLibrary(boxes: shelves, currentID: current), dropped)
    }
}

/// One box with lenient items.
struct LenientBox: Decodable {
    let id: UUID
    let name: String
    let items: [Lenient<ShelfItem>]
    let frame: Rect2D?
    let dock: DockEdge?
    let viewMode: Shelf.ViewMode
    let updatedAt: Date
    let shown: Lenient<String>?

    /// The box with its valid, distinct items under the cap, and how many items it lost; nil when the box itself
    /// is invalid.
    func shelf() -> (Shelf, droppedItems: Int)? {
        guard
            let empty = try? Shelf(
                id: id, name: name, frame: frame, dock: dock, viewMode: viewMode, updatedAt: updatedAt,
                shown: BoxPresentation.Base(stored: shown?.value))
        else { return nil }
        let valid = items.compactMap(\.value)
        let (filled, report) = empty.adding(valid, cap: ShelfLibrary.maxItemsPerBox)
        return (filled, items.count - valid.count + report.duplicates.count + report.overCap.count)
    }
}

/// A value that decodes to nil instead of failing.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

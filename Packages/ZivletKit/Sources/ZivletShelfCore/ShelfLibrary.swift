import Foundation

/// Every box and which one is current (OWN-APP-1, D-M5b-18). Drops go to the current box, which is the most
/// recently used; ⌥ makes a new box. At most 8 boxes and 2,000 items per box. Immutable like its boxes.
public struct ShelfLibrary: Sendable, Equatable, Codable {
    public enum Destination: Sendable, Equatable {
        case current, newBox
    }

    public static let maxBoxes = 8
    public static let maxItemsPerBox = 2_000
    static let baseName = "Box"

    public let boxes: [Shelf]
    public let currentID: UUID?

    /// A `currentID` that names none of `boxes` is dropped.
    public init(boxes: [Shelf] = [], currentID: UUID? = nil) {
        self.boxes = boxes
        self.currentID = boxes.contains { $0.id == currentID } ? currentID : nil
    }

    public var current: Shelf? { boxes.first { $0.id == currentID } }

    /// Adds `items` to the current box (made as "Box" when there is none) or to a new numbered box, which becomes
    /// current. The box is marked used at `now`.
    public func adding(_ items: [ShelfItem], to destination: Destination, now: Date) throws(ShelfError) -> (
        ShelfLibrary, AddReport
    ) {
        let target: Shelf
        if destination == .current, let current {
            target = current
        } else {
            target = try newBox()
        }
        let (filled, report) = target.adding(items, cap: Self.maxItemsPerBox)
        return (upserting(filled.touched(at: now)), report)
    }

    /// The library with `shelf` in place of the box with its id; a box the library does not hold is ignored.
    public func replacing(_ shelf: Shelf) -> ShelfLibrary {
        guard boxes.contains(where: { $0.id == shelf.id }) else { return self }
        return ShelfLibrary(boxes: boxes.map { $0.id == shelf.id ? shelf : $0 }, currentID: currentID)
    }

    /// Removes a box; when it was current, the most recently used other box becomes current.
    public func removingBox(_ id: UUID) -> ShelfLibrary {
        let rest = boxes.filter { $0.id != id }
        let next = currentID == id ? rest.max { $0.updatedAt < $1.updatedAt }?.id : currentID
        return ShelfLibrary(boxes: rest, currentID: next)
    }

    /// Makes a held box current; an unknown id changes nothing.
    public func makingCurrent(_ id: UUID) -> ShelfLibrary {
        guard boxes.contains(where: { $0.id == id }) else { return self }
        return ShelfLibrary(boxes: boxes, currentID: id)
    }

    private func newBox() throws(ShelfError) -> Shelf {
        guard boxes.count < Self.maxBoxes else { throw .tooManyBoxes }
        return try Shelf.empty(name: nextName())
    }

    /// "Box", then "Box 2", "Box 3" …: the first name no box uses.
    private func nextName() -> String {
        let used = Set(boxes.map(\.name))
        let candidates = [Self.baseName] + (2...(Self.maxBoxes + 1)).map { "\(Self.baseName) \($0)" }
        return candidates.first { !used.contains($0) } ?? "\(Self.baseName) \(boxes.count + 1)"
    }

    /// Replaces the box with `shelf`'s id, or appends it, and makes it current.
    private func upserting(_ shelf: Shelf) -> ShelfLibrary {
        let held = boxes.contains { $0.id == shelf.id }
        let next = held ? boxes.map { $0.id == shelf.id ? shelf : $0 } : boxes + [shelf]
        return ShelfLibrary(boxes: next, currentID: shelf.id)
    }
}

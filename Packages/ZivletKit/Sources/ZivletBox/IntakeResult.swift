import Foundation
import ZivletShelfCore

/// What one drop gave the box (P2-141): the new items, the refused ones as "name: reason" lines for the action card
/// (never logged), and the bytes of the copies the box now owns.
nonisolated public struct IntakeResult: Equatable, Sendable {
    /// The refusal when nothing in the drop could be added (19c §4.2).
    public static let nothingUsable = "Only items stored on this Mac can be added"

    public let items: [ShelfItem]
    public let rejected: [String]
    public let ownedBytes: Int64
    /// Files written into the box's storage that did not become items (a promise whose bookmark failed): the
    /// controller sends them to the Trash so nothing lingers unreachable.
    public let strays: [URL]

    public init(items: [ShelfItem], rejected: [String], ownedBytes: Int64, strays: [URL] = []) {
        self.items = items
        self.rejected = rejected
        self.ownedBytes = ownedBytes
        self.strays = strays
    }

    /// The same result with "N items couldn't be added" for `count` pasteboard items that were not files.
    func noting(notFiles count: Int) -> IntakeResult {
        guard count > 0 else { return self }
        return IntakeResult(
            items: items, rejected: rejected + [BoxCopy.notFiles(count)], ownedBytes: ownedBytes, strays: strays)
    }
}
